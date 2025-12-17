;   ********************************************************************************************
;   *** MINIMAL DINO RUN is an endless runner based on Google's Chrome "Dinosaur Game"       ***
;   *** original game created by Sebastien Gabriel, Alan Bettes, and Edward Jung in 2014     *** 
;   *** Adapted to Minimal 64x4 assembly by Mateusz Matysiak (Hellboy73) December 2025       ***
;   *** Software repository: https://github.com/hellboy73/M64x4-Dino-Run                     ***
;   *** Game requires:                                                                       ***
;   *** Joystick                                                                             ***
;   *** Minimal64x4 computer by Slu4 https://github.com/slu4coder/Minimal-64x4-Home-Computer ***
;   *** Expansion card by Hans61 https://github.com/hans61/Minimal-64x4-Expansion            ***
;   *** Change log:                                                                          ***
;   ***  v0.9 13.12.2025 initial working emulator firendly preview (no sound, no expansion)  ***
;   ***  v1.0 17.12.2025 full version with VS detection and joystick support (no sound)      *** 
;   ********************************************************************************************

#org 0x8000
	JPA init

;   **************************************
;   *** fast subroutines               ***
;   *** include fast single page jumps ***
;   **************************************
					; ******************
clear_buffer:   	; *** clears buffer area 
					; *** very fast and based on OS_Clear , uses Z0 Z1
					; *** 5.23-0.9s / 2048 = 0,0021142578125s = 2.1 ms 
					; ******************
				LDI <Buffer-2 	STB cbuf_loopx+1	; set start index
                LDI >Buffer-2	STB cbuf_loopx+2	; we need to clear more than buffer to avoid glitches on begining and end while scrolling sprites
				MIZ 62, Z1							; height in pixels stored in Z1 counter - no need to clear 6pix of ground
  cbuf_loopy:   MIZ 10,Z0                           ; width in long words stored in Z0 counter
  cbuf_loopx:   CLL 0x0000							; clear long word
                AIB 4,cbuf_loopx+1					; add 4 bytes longword		
                DEZ Z0 FGT cbuf_loopx         		; check if end of line                
                AIW 24,cbuf_loopx+1 				; move to next line
				DEZ Z1 FGT cbuf_loopy           	; check if last line cleared
				RTS			

;   *************************************
;   *** Initial Section               ***
;   *************************************
init:
		LDI 0xfe STB 0xffff							; reset stack
		MIW 0x45a1 _RandomState						; initiate pseudo-random generator with wharever
		MIW 0xf32d _RandomState+2
		JPS _ClearVRAM                              ; clear screen
		JPS init_speedcopy
													; draw initial screen
		MIB 1 _dino_state							; dino still
		JPS clear_buffer
		JPS Calculate_dino_pos
		JPS Draw_Moon			
		JPS Draw_Cloud
		JPS Draw_Ground
		JPS Draw_Dino
		JPS SpeedCopy			
		MIZ  9 _YPos MIZ 17 _XPos JPS _Print   "MINIMAL DINO RUN" 0
		MIZ 11 _YPos MIZ 16 _XPos JPS _Print  "push fire to start" 0
		JPS Wait_fire
start:												; initialize all the game variables before game starts 
		MIB 0 	_game_level
		MIB 0 	_score
		MIB "0" _score_string	MIB "0" _score_string+1	MIB "0" _score_string+2	MIB "0" _score_string+3	MIB "0" _score_string+4
		MIB 3 	_game_speed
		MIB 1 	_dino_state
		MIB 0 	_dino_jump_stage	
		MIB 55	_enemy1_countdown
		MIB 0 	_enemy1_x_pos	
		MIB 93	_enemy2_countdown
		MIB 0 	_enemy2_x_pos	
		JPA action_loop
	
;   *************************************
;   *** Game Over screen              ***
;   *************************************
game_over:
		JPS SpeedCopy							; fast Buffer copy to Playfield
		MIZ 11 _YPos MIZ 26-9 _XPos JPS _Print "G A M E  O V E R" 0		; game over message
		JPS HiScore														; calculate and display hiscore
		LDI 60   JAS wait_frames            							; wait 60 frames = 1 sec 
		JPS Wait_fire													; wait for fire pressed
		JPA	start

;   *************************************
;   *** Main game action loop         ***
;   *************************************
action_loop:
		JPS waitVsync							; top raster wait 
		JPS SpeedCopy							; fast Buffer copy to Playfield
		JPS clear_buffer
		JPS read_joystick
		JPS Animate_sprites
		JPS Control_section
		JPS Calculate_dino_pos
		JPS Draw_Moon
		JPS Draw_Cloud	
		JPS Animate_ground
		JPS Draw_Ground
		JPS	Enemy1
		JPS Enemy2
		JPS Collision_detection					; if collision detected set _dino_state to 5 (dead) 
		JPS Draw_Dino
		JPS Score
		LDB _dino_state	CPI 5 BEQ game_over		; game over jump  	_dino_state: 1-still 2-runs 3-jumps 4-ducks 5-dead
	JPA action_loop								; infinite loop

;   *************************************
;   *** Subroutines                   ***
;   *************************************
					; ******************
Wait_fire:			; *** wait fire press and do the blinking if dino is still
					; *** at the same time run randomizer
					; ******************
		JPS waitVsync										; top raster wait and detection
		JAS _Random											; roll the dice 
		LDB _dino_state 	CPI 1	BNE Wf_key_read			; is Dino in still state? beginning of game and do blinking, no blinking on dead dino

	Wf_blink1:	LDB _blink_counter1 CPI 0 BEQ Wf_blink2 	; check if counter zero (eye closed) 
				MIB 0xD8 Playfield+2+3008					; set the eye open
				DEB _blink_counter1		JPA Wf_blink_exit	; decr counter
	Wf_blink2:	MIB 0xF8 Playfield+2+3008					; set the eye closed
				DEB _blink_counter2	BNE Wf_blink_exit		; dec counter2, 
				MIB 0xff _blink_counter1	MIB 10 _blink_counter2	; if zero reset both counters
	Wf_blink_exit:
	Wf_key_read:
				JPS read_joystick
				LDB _up CPI 1 BNE Wait_fire	
		RTS

_blink_counter1:	0xff
_blink_counter2:	10

						;******************
Score:					;* calculating and displaying game scores, always increase by 1 point only 
						;* progressing levels based on scores
						;* input: _game_speed
						;******************
			DEB	_score_counter BNE score_exit				
			LDI 9 	SUB _game_speed	STB _score_counter						; new score counter set based on _game_speed (10 can be adjusted) 
			INB	_score		LDB _score		CPI 100 	BNE score_add		; increase score byte, check if 100 points
			CLB _score		INB _game_level									; if yes, increase the game level
	level2:		LDB _game_level	CPI 2 	BNE level10		MIB 4 _game_speed 	; after level 2  speed = 4
	level10:	LDB _game_level	CPI 10 	BNE level17		MIB 5 _game_speed 	; after level 10 speed = 5
	level17:	LDB _game_level	CPI 17 	BNE score_add	MIB 6 _game_speed 	; after level 17 speed = 6 (top speed)
	score_add:	INB _score_string+4	LDB _score_string+4	CPI ":" BNE score_disp	MIB "0" _score_string+4
				INB _score_string+3	LDB _score_string+3	CPI ":" BNE score_disp	MIB "0" _score_string+3
				INB _score_string+2	LDB _score_string+2	CPI ":" BNE score_disp	MIB "0" _score_string+2
				INB _score_string+1	LDB _score_string+1	CPI ":" BNE score_disp	MIB "0" _score_string+1
				INB _score_string	LDB _score_string	CPI ":" BNE score_disp	MIB "0" _score_string
	score_disp:
			MIZ 6 _YPos MIZ 38 _XPos 
			JPS _Print
			_score_string:		"00000" 0 
			RTS
	level_disp:									;<<<<<<<<< for troubleshooting only, disable in final release
			MIZ 6 _YPos MIZ 7 _XPos 
			JPS _Print  "Lvl:" 0 LDB _game_level JAS _PrintHex
			JPS _Print " Spd:" 0 LDB _game_speed JAS _PrintHex
			JPA score_exit
score_exit:
			RTS

_score_counter:	1			; how many frames till a point? variable set by score procedure
_score:			0			; variable to detect every 100 points

						;******************
HiScore:				;* checking if score is bigger than hiscore and copy if necessary 
						;* displaying hiscore 
						;* input: _score_string
						;******************
			CBB _hiscore_string+0	_score_string+0	BGT hiscore_hit BNE hiscore_disp; score bigger than hiscore then hiscore hit, if less skip and print old hiscore, if equal see further
			CBB _hiscore_string+1	_score_string+1	BGT hiscore_hit BNE hiscore_disp
			CBB _hiscore_string+2	_score_string+2	BGT hiscore_hit BNE hiscore_disp
			CBB _hiscore_string+3	_score_string+3	BGT hiscore_hit BNE hiscore_disp
			CBB _hiscore_string+4	_score_string+4	BGT hiscore_hit BNE hiscore_disp
			JPA hiscore_disp
	hiscore_hit:										; copy score to hiscore
			MBB _score_string+0 _hiscore_string+0
			MBB _score_string+1 _hiscore_string+1
			MBB _score_string+2 _hiscore_string+2
			MBB _score_string+3 _hiscore_string+3
			MBB _score_string+4 _hiscore_string+4
	hiscore_disp:										; print hiscore
			MIZ 6 _YPos MIZ 29 _XPos JPS _Print "HI " 0
			JPS _Print
			_hiscore_string:	 "00000" 0 
		RTS

						;******************
Collision_detection:	;* if collision detected, then set dino state to 5 (dead)  
						;* y coords are 0 on top of the screen, bottom is 67
						;* input:	_dino_y_top		_dino_y_bottom		
						;* 			_enemy1_y_top	_enemy1_y_bottom	_enemy1_x_pos	_enemy1_sprite_width
						;* 			_enemy2_y_top	_enemy2_y_bottom	_enemy2_x_pos	_enemy2_sprite_width
						;******************
	cd_enemy1:
 		LDB _enemy1_x_pos 	ADB _enemy1_sprite_width	STB _enemy_x_right	
		CBB _dino_x_right		_enemy1_x_pos	BGT cd_enemy2		; check x coords collision, if not skip further checks
		CBB _enemy_x_right		_dino_x_left	BGT cd_enemy2
		CBB _dino_y_bottom		_enemy1_y_top	BGT cd_enemy2		; check y coords collision, if not , no collision
		CBB _enemy1_y_bottom	_dino_y_top		BGT cd_enemy2
		JPA coll_detected
	cd_enemy2:						
 		LDB _enemy2_x_pos 	ADB _enemy2_sprite_width	STB _enemy_x_right	
		CBB _dino_x_right		_enemy2_x_pos	BGT cd_exit			; check x coords collision, if not skip further checks
		CBB _enemy_x_right		_dino_x_left	BGT cd_exit
		CBB _dino_y_bottom		_enemy2_y_top	BGT cd_exit			; check y coords collision, if not , no collision
		CBB _enemy2_y_bottom	_dino_y_top		BGT cd_exit
	coll_detected:
		MIB 5 _dino_state
		JPS Calculate_dino_pos
	cd_exit:
		RTS

_dino_x_left:	6		; dino x coords are constant
_dino_x_right:	6		; dino x coords are constant
_enemy_x_right:	0		; variable for calculations

						;******************
Control_section:		;* set dino state based on joystick 
						;* input: 	_up: _down: _space: _pressed: [0/1]
						;* output: 	_dino_state: 1-still 2-runs 3-jumps 4-ducks 5-dead
						;******************
	cs_jump:	LDB	_dino_state	CPI 3	BEQ cs_exit				; is dino during jump? if yes, skip further controls (continue jump)
	cs_up:		LDB _up			CPI 1	BNE cs_down		MIB 3 _dino_state	JPA cs_exit		; set dino into jump stage
	cs_down:	LDB _down		CPI 1	BNE cs_other	MIB 4 _dino_state	JPA cs_exit 	; set dino into ducking stage
	cs_other:	MIB 2 _dino_state															; set dino into runing stage
	cs_exit:	RTS

						;******************
Animate_sprites:		;* progress all the animations by one frame 
						;* swap sprites once in a defined number of frames
						;******************
	anim_run:
			DEB	_run_counter  LDB _run_counter CPI 0 BNE anim_run_exit		; dec counter, if not zero - exit
			LDI 10 	SUB _game_speed	STB _run_counter						; initiate animation cycle - depending on game speed
	anim_run_read_ptr:	
			LDB _run_pos		LAB _run_cycle		STB Dino_runs_ptr		; read indexed pointer (_run_pos is an index)
			LDB _run_pos		LAB _run_cycle+1	STB Dino_runs_ptr+1
			LDB Dino_runs_ptr+1 CPI 0xff			BEQ anim_run_loops		; check if cycle reached end marker 0xffff MSB=0xff if yes, then go again
			INB _run_pos		INB _run_pos								; inc index by 2 (pointers take 2 bytes)  
			JPA anim_run_exit
	anim_run_loops:
			MIB 0 _run_pos		JPA anim_run_read_ptr						; reset animation position to zero and read pointers again
	anim_run_exit:
	anim_duck:
			DEB	_duck_counter  LDB _duck_counter CPI 0 BNE anim_duck_exit	; dec counter, if not zero - exit
			LDI 10 	SUB _game_speed	STB _duck_counter						; initiate animation cycle - depending on game speed
	anim_duck_read_ptr:	
			LDB _duck_pos		LAB _duck_cycle		STB Dino_ducks_ptr		; read indexed pointer (_duck_pos is an index)
			LDB _duck_pos		LAB _duck_cycle+1	STB Dino_ducks_ptr+1
			LDB Dino_ducks_ptr+1 CPI 0xff			BEQ anim_duck_loops		; check if cycle reached end marker 0xffff MSB=0xff if yes, then go again
			INB _duck_pos		INB _duck_pos								; inc index by 2 (pointers take 2 bytes)  
			JPA anim_duck_exit
	anim_duck_loops:
			MIB 0 _duck_pos		JPA anim_duck_read_ptr						; reset animation position to zero and read pointers again
	anim_duck_exit:
	anim_ptero:
			DEB	_ptero_counter  LDB _ptero_counter CPI 0 BNE anim_ptero_exit	; dec counter, if not zero - exit
			MIB 10 _ptero_counter												; initiate animation cycle - every 10 frames
	anim_ptero_read_ptr:	
			LDB _ptero_pos		LAB _ptero_cycle		STB Ptero_ptr		; read indexed pointer (_ptero_pos is an index)
			LDB _ptero_pos		LAB _ptero_cycle+1		STB Ptero_ptr+1
			LDB Ptero_ptr+1 CPI 0xff			BEQ anim_ptero_loops		; check if cycle reached end marker 0xffff MSB=0xff if yes, then go again
			INB _ptero_pos		INB _ptero_pos								; inc index by 2 (pointers take 2 bytes)  
			JPA anim_ptero_exit
	anim_ptero_loops:
			MIB 0 _ptero_pos		JPA anim_ptero_read_ptr					; reset animation position to zero and read pointers again
	anim_ptero_exit:
			RTS

_run_cycle: 	Dino_runs1  Dino_runs2  0xffff
_run_pos: 		0
_run_counter: 	7
_duck_cycle: 	Dino_ducks1  Dino_ducks2 0xffff	
_duck_pos: 		0
_duck_counter: 	7
_ptero_cycle: 	Ptero2  	Ptero1  	0xffff
_ptero_pos: 	0
_ptero_counter: 14

						;******************
Calculate_dino_pos:		;* Setting dino sprite variables:
						;* output: 	_dino_sprite_pointer	_dino_pos_pointer	_dino_height	_dino_width
						;* 			_dino_y_top	_dino_y_bottom	
						;* input: 	_dino_state: 1-still 2-runs 3-jumps 4-ducks 5-dead
						;* uses: 	Z3	dino_jump_y_coords
						;******************
		LDB	_dino_state CPI 3 BEQ cdp_jumps						; is he jumping? continue jumping and exit
		LDB _dino_state CPI 4 BEQ cdp_ducks						; is he ducking? set ducking params
		LDB _dino_state CPI 2 BEQ cdp_runs						; is he running? set running params
		LDB _dino_state CPI 1 BEQ cdp_still						; is he still? set still params
	cdp_dead:													; if none of above, he must be dead
			MIB 22 _dino_height		MIB 3 _dino_width			; populating sprite size	
			MBB Dino_dead_ptr		_dino_sprite_pointer		; populating pointers for dead
			MBB Dino_dead_ptr+1 	_dino_sprite_pointer+1		
			MBB _dino_prev_pointer  _dino_pos_pointer			; populating sprite position from last stored pointer
			MBB _dino_prev_pointer+1  _dino_pos_pointer+1
			RTS
	cdp_still:
			MIB 22 _dino_height		MIB 3 _dino_width			; populating sprite size	
			MBB Dino_still_ptr		_dino_sprite_pointer		; populating pointers for dead
			MBB Dino_still_ptr+1 	_dino_sprite_pointer+1		
			MIW Buffer+2881 		_dino_pos_pointer			; populating sprite position	
			RTS
	cdp_runs:
			MIB 22 _dino_height		MIB 3 _dino_width			; populating sprite size	
			MBB Dino_runs_ptr		_dino_sprite_pointer		; populating pointers for dead
			MBB Dino_runs_ptr+1 	_dino_sprite_pointer+1		
			MIW Buffer+2881 _dino_pos_pointer					; populating sprite position	;MBB Dino_still_ptr		_dino_sprite_pointer		;populating pointers for jump
			MBB _dino_pos_pointer	_dino_prev_pointer  		; keep last pointer for dead dino
			MBB _dino_pos_pointer+1	_dino_prev_pointer+1		; keep last pointer for dead dino
			MIB 50 _dino_y_top		MIB 45+22 _dino_y_bottom	; set Y coords for collision detection (45, 67)
			RTS
	cdp_jumps:	
			MIB 22 _dino_height		MIB 3 _dino_width			; populating sprite size	
			MBB Dino_still_ptr		_dino_sprite_pointer		; populating sprite pointers for jump
			MBB Dino_still_ptr+1 	_dino_sprite_pointer+1		; populating sprite pointers for jump
			LDB _dino_jump_stage	LAB dino_jump_y_coords 		; read y cord for this stage of jump
			STB _dino_y_top		STZ Z3		INZ Z3				; populate Y coords	,set loop counter in Z3
			LDB _dino_y_top		ADI 15 	STB _dino_y_bottom		; calculate Y coords for collision detection (ADI 22)
			MIW	Buffer+1			_dino_pos_pointer			; top position y=0 
		multipl_loop:	DEZ Z3	BEQ multipl_exit				; populate _dino_pos_pointer by multiplying y coord by 64 
						AIW 64	_dino_pos_pointer	JPA multipl_loop
		multipl_exit:
			MBB _dino_pos_pointer	_dino_prev_pointer  		; keep last pointer for dead dino
			MBB _dino_pos_pointer+1	_dino_prev_pointer+1		; keep last pointer for dead dino
			INB _dino_jump_stage
			LDB _down 	CPI 1 BNE cdp_single_jump	INB _dino_jump_stage	; if down pressed then double the jump speed
		cdp_single_jump:
			LDB _dino_jump_stage	LAB dino_jump_y_coords	CPI 0xff 	BEQ cdp_jump_end 	; check next stage (is it he end?)
			RTS
		cdp_jump_end:
			CLB _dino_jump_stage		; reset jump state to beginning
			MIB  2 _dino_state			; end jump, back to running state
			RTS
	cdp_ducks:
			MIB 13 _dino_height		MIB 4 _dino_width			; populating sprite size	
			MBB Dino_ducks_ptr		_dino_sprite_pointer		; populating pointers for dead dino
			MBB Dino_ducks_ptr+1 	_dino_sprite_pointer+1		
			MIW Buffer+2881+576		_dino_pos_pointer			; populating sprite position	
			MIW Buffer+2881 		_dino_prev_pointer			; keep this pointer for dead dino
			MIB 45+9 _dino_y_top	MIB 45+22 _dino_y_bottom	; set Y coords for collision detection
			RTS

_dino_jump_stage: 0		
_dino_y_top:	0
_dino_y_bottom:	0

				;******************
Draw_Dino:		;* putting right dino sprite at required position in buffer
				;* includes putting overlay on legs 
				;* uses _dino_state: 1-still 2-runs 3-jumps 4-ducks 5-dead
				;* Z7 Z6
				;******************
		MBZ _dino_height Z7						; populating sprite height in lines 
		dd_loop1:								; outer loop (22 lines high) 
			MBZ _dino_width Z6					; populating sprite width in bytes 
			dd_loop2:							; inner loop (3 bytes in a row)
				LDR _dino_sprite_pointer 		; byte copy
				ORR _dino_pos_pointer			; comment this out for regular copy without OR operation
				STR _dino_pos_pointer			; 
				INW _dino_sprite_pointer 	INW _dino_pos_pointer
				DEZ Z6 		BNE dd_loop2		; decr counter and repeat if not zero
			AIW 64 _dino_pos_pointer	SBW _dino_width _dino_pos_pointer		; skip 64 - width [bytes]
			DEZ Z7	BNE dd_loop1				; decr counter and go to next line if not zero 

	dd_overlay:									; now we apply overlay on dinos legs	
		LDB _dino_state	CPI 3 BEQ dd_exit		; skip it id dino jumps or dead
		LDB _dino_state	CPI 5 BEQ dd_exit
		DEB _dino_width							; outline width is one byte less than dino sprite width
		MIZ 5 Z7								; height of outline (same as ground height) 5 lines
		MIW Buffer+4032-64 _dino_pos_pointer	; set beginning of outline same address than ground address ...
		INW _dino_pos_pointer					; ... plus one byte
		ddo_loop1:
		MBZ _dino_width Z6						
			ddo_loop2:
				LDR _dino_sprite_pointer 		; take byte
				ANR _dino_pos_pointer			; AND it with screen gfx
				STR _dino_pos_pointer			; store back on the screen
				INW _dino_sprite_pointer 	INW _dino_pos_pointer
				DEZ Z6 		BNE ddo_loop2		; decr counter and repeat if not zero
			AIW 64 _dino_pos_pointer	SBW _dino_width _dino_pos_pointer		; skip 64 - width [bytes]
			DEZ Z7	BNE ddo_loop1				; decr counter and go to next line if not zero 
	dd_exit:
		RTS

_dino_sprite_pointer:	0x0000		; i.e. Dino_still 	
_dino_pos_pointer:		0x0000		
_dino_prev_pointer:		0x0000		; just to know last position in case dino dies
_dino_height:			22			; in lines
_dino_width:			3 			; in bytes
_dino_state: 			1			; 1-still 2-runs 3-jumps 4-ducks 5-dead

				;******************
Enemy1:			;* Enemy One handling procedure (there are two enemies potentially on the screen)
				;* runs enemy scroll step once related countdown reaches zero
				;* uses:	_game_speed	Z0 Z3 Z4 Z6 Z7
				;******************
		LDB _enemy1_countdown	CPI 0 	BEQ enemy1_run				; first check if this enemy is on the run (countdown = 0) 
																	; now check if its safe to initiate enemy1 (based on enemy2 position) 
		CIB 24 _enemy2_x_pos BGT	enemy1_exit						; enemy1_x_pos bigger than 20 then exit (enemies too close eachother)
																	; check if a game progressed by one whole byte to dec the countdown
		LDB _game_speed ADB	_enemy1_scroll  STB _enemy1_scroll		; increase temp variable by game speed value
		LR3	CPI 0	BEQ enemy1_exit									; shift right 3 bits check if game moved 8 bits or more , if not skip the procedure
		LDB _enemy1_scroll		ANI 0x07	STB _enemy1_scroll		; if result is >7 then clear upper bits
		DEB _enemy1_countdown	BNE enemy1_exit						; and decrease the countdown counter

		MIB 40 	_enemy1_x_pos										; initiate enemy run, set position at the end of screen
		CIB 2 _game_level	BGT e1_ptero							; pick enemy based on level (pteros only after level 2)
				JAS _Random 	ANI 0x07 	ADI 4 	STB _enemy1_index	JPA e1_pop		; skip pteros (first 4 enemies)
	e1_ptero:	JAS _Random 	ANI 0x0f 			STB _enemy1_index					; randomize and set enemy index - pick the enemy (16 variants) 
	e1_pop:	LDB _enemy1_index	LAB enemies_height		STB _enemy1_sprite_height	; populate enemy parameters
			LDB _enemy1_index	LAB enemies_width		STB _enemy1_sprite_width
			LDB _enemy1_index	LAB enemies_y_top		STB _enemy1_y_top
			LDB _enemy1_index	LAB enemies_y_bottom	STB _enemy1_y_bottom
	enemy1_run:															; calculate enemy scroll, enemy x pos, draw it in buffer, scroll buffer, copy buffer to the screen 
			LDB _game_speed ADB	_enemy1_scroll  STB _enemy1_scroll		; increase scroll variable by game speed value
			LR3	CPI 0	BEQ e1_cont										; shift right 3 bits check if game moved 8 bits or more , if not skip the procedure
			LDB _enemy1_scroll		ANI 0x07	STB _enemy1_scroll		; if result is >7 then clear upper bits
			DEB _enemy1_x_pos		BEQ enemy1_run_ends					; if scroll x pos reaches zero, end enemy run
		e1_cont:			
			JPS Clear_sprite_buffer						; clear sprite buffer
														; copy sprite to buffer
			MIW Buffer-1600	_enemy1_buffer_pointer								; populate pointers
			LDB	_enemy1_index	LAB enemies_ptr_lsb	STB	_enemy1_tmp_pointer		; load enemy sprite pointer from table based on enemy index	
			LDB	_enemy1_index	LAB enemies_ptr_msb	STB	_enemy1_tmp_pointer+1	; using proxy temp pointer as a pointer is pointing to actual pointer 
			LDR _enemy1_tmp_pointer		STB _enemy1_sprite_pointer				; store it in sprite pointer
			INB _enemy1_tmp_pointer
			LDR _enemy1_tmp_pointer		STB _enemy1_sprite_pointer+1

			MBZ _enemy1_sprite_height Z7			; poputalting sprite height
			e1_loop1:								; outer loop (Z7 lines high) 
					MBZ _enemy1_sprite_width Z6		; populating sprite width in bytes 
			e1_loop2:								; inner loop (Z6 bytes)
					LDR _enemy1_sprite_pointer 	STR _enemy1_buffer_pointer		; actual byte copy
					INW _enemy1_sprite_pointer 	INW _enemy1_buffer_pointer
					DEZ Z6 		BNE e1_loop2		; decr counter and repeat if not zero
					AIW 64 _enemy1_buffer_pointer	SBW _enemy1_sprite_width _enemy1_buffer_pointer		; skip 64 - width [bytes]
					DEZ Z7	BNE e1_loop1			; decr counter and go to next line if not zero 
													; now scroll the sprite buffer
				LDI 7 SUB  _enemy1_scroll STZ Z4
				LDZ Z4 	CPI 0 BEQ e1_scroll_end		; if 0 times then skip
			e1_scroll:								; scroll it _scroll times
				JPS Scroll_sprite_buffer		
				DEZ Z4	BNE e1_scroll
			e1_scroll_end:							; copy scrolled sprite from sprite buffer to actual buffer to required x_pos
													; calculate address based on x_pos
				MIW	Buffer-4 _enemy1_pos_pointer						; top position y=0 
				MBZ _enemy1_y_top Z3	INZ Z3
			e1_multipl_loop:	DEZ Z3	BEQ e1_multipl_exit				; populate _enemy_pos_pointer by multiplying y coord by 64 
								AIW 64	_enemy1_pos_pointer		JPA e1_multipl_loop
			e1_multipl_exit:
				ABW _enemy1_x_pos 	_enemy1_pos_pointer
				MIW Buffer-1600 	_enemy1_buffer_pointer
				MBZ _enemy1_sprite_height Z7		; poputalting sprite height
			e1_loop3:								; outer loop (22 lines high) 
					MIZ 4 Z6						; populating sprite width in bytes (whole buffer is 4 bytes) 
			e1_loop4:								; inner loop (4 bytes in a row)
					LDR _enemy1_buffer_pointer 	ORR _enemy1_pos_pointer	STR _enemy1_pos_pointer		; actual byte copy
					INW _enemy1_buffer_pointer 	INW _enemy1_pos_pointer
					DEZ Z6 		BNE e1_loop4		; decr counter and repeat if not zero
					AIW 60 _enemy1_pos_pointer	AIW 60 _enemy1_buffer_pointer
					DEZ Z7	BNE e1_loop3			; decr counter and go to next line if not zero 
			RTS
	enemy1_run_ends:	
		JPS _Random ANI 0x1f STB _enemy1_countdown					; repopulate countdown
		INB _enemy1_countdown										; prevent zero
	enemy1_exit:	
		RTS

_enemy1_countdown:		0
_enemy1_x_pos:			0
_enemy1_scroll:			0
_enemy1_sprite_pointer:	0x0000	; this is a variable which is modified during sprite copy 
_enemy1_tmp_pointer:	0x0000 	; pointer to a pointer
_enemy1_pos_pointer:	0x0000	; this is a variable which is modified during sprite copy 
_enemy1_sprite_height:	0
_enemy1_sprite_width:	0
_enemy1_y_top:			0 		; for collision detection
_enemy1_y_bottom:		0		; for collision detection
_enemy1_buffer_pointer:	0x0000	; buffer for sprite scrolling at Buffer-1600	
_enemy1_index:			0		; index of currently running enemy , to be randomized each enemy starts its run

				;******************
Enemy2:			;* Enemy Two handling procedure (there are two enemies potentially on the screen)
				;* runs enemy scroll step once related countdown reaches zero
				;* uses:	_game_speed	Z0 Z3 Z4 Z6 Z7
				;******************
		CIB 1 _game_level	BGT e2_active	RTS						; enemy 2 only after level 1
	e2_active:
		LDB _enemy2_countdown	CPI 0 	BEQ enemy2_run				; first check if this enemy is on the run (countdown = 0) 
																	; now check if its safe to initiate enemy1 (based on enemy2 position) 
		CIB 24 _enemy1_x_pos BGT	enemy2_exit						; enemy1_x_pos bigger than 20 then exit (enemies too close eachother)
																	; check if a game progressed by one whole byte to dec the countdown
		LDB _game_speed ADB	_enemy2_scroll  STB _enemy2_scroll		; increase temp variable by game speed value
		LR3	CPI 0	BEQ enemy2_exit									; shift right 3 bits check if game moved 8 bits or more , if not skip the procedure
		LDB _enemy2_scroll		ANI 0x07	STB _enemy2_scroll		; if result is >7 then clear upper bits
		DEB _enemy2_countdown	BNE enemy2_exit						; and decrease the countdown counter

		MIB 40 	_enemy2_x_pos										; initiate enemy run, set position at the end of screen
		CIB 2 _game_level	BGT e2_ptero							; pick enemy based on level (pteros only after level 2)
				JAS _Random 	ANI 0x07 	ADI 4 	STB _enemy2_index	JPA e2_pop		; skip pteros (first 4 enemies)
	e2_ptero:	JAS _Random 	ANI 0x0f 			STB _enemy2_index					; randomize and set enemy index - pick the enemy
	e2_pop:	LDB _enemy2_index	LAB enemies_height		STB _enemy2_sprite_height		; populate enemy parameters
			LDB _enemy2_index	LAB enemies_width		STB _enemy2_sprite_width
			LDB _enemy2_index	LAB enemies_y_top		STB _enemy2_y_top
			LDB _enemy2_index	LAB enemies_y_bottom	STB _enemy2_y_bottom
	enemy2_run:															; calculate enemy scroll, enemy x pos , draw it in buffer, scroll buffer, copy buffer to the screen 
			LDB _game_speed ADB	_enemy2_scroll  STB _enemy2_scroll		; increase scroll variable by game speed value
			LR3	CPI 0	BEQ e2_cont										; shift right 3 bits check if game moved 8 bits or more , if not skip the procedure
			LDB _enemy2_scroll		ANI 0x07	STB _enemy2_scroll		; if result is >7 then clear upper bits
			DEB _enemy2_x_pos		BEQ enemy2_run_ends					; if scroll x pos reaches zero, end enemy run
		e2_cont:			
			JPS Clear_sprite_buffer						; clear sprite buffer
														; copy sprite to buffer
			MIW Buffer-1600	_enemy2_buffer_pointer								; populate pointers
			LDB	_enemy2_index	LAB enemies_ptr_lsb	STB	_enemy2_tmp_pointer		; load enemy sprite pointer from table based on enemy index	
			LDB	_enemy2_index	LAB enemies_ptr_msb	STB	_enemy2_tmp_pointer+1	; using proxy temp pointer as a pointer is pointing to actual pointer 
			LDR _enemy2_tmp_pointer		STB _enemy2_sprite_pointer				; store it in sprite pointer
			INB _enemy2_tmp_pointer
			LDR _enemy2_tmp_pointer		STB _enemy2_sprite_pointer+1

			MBZ _enemy2_sprite_height Z7			; poputalting sprite height
			e2_loop1:								; outer loop (Z7 lines high) 
					MBZ _enemy2_sprite_width Z6		; populating sprite width in bytes 
			e2_loop2:								; inner loop (Z6 bytes)
					LDR _enemy2_sprite_pointer 	STR _enemy2_buffer_pointer		; actual byte copy
					INW _enemy2_sprite_pointer 	INW _enemy2_buffer_pointer
					DEZ Z6 		BNE e2_loop2		; decr counter and repeat if not zero
					AIW 64 _enemy2_buffer_pointer	SBW _enemy2_sprite_width _enemy2_buffer_pointer		; skip 64 - width [bytes]
					DEZ Z7	BNE e2_loop1			; decr counter and go to next line if not zero 
													; now scroll the sprite buffer
				LDI 7 SUB  _enemy2_scroll STZ Z4
				LDZ Z4 	CPI 0 BEQ e2_scroll_end		; if 0 times then skip
			e2_scroll:								; scroll it _scroll times
				JPS Scroll_sprite_buffer		
				DEZ Z4	BNE e2_scroll
			e2_scroll_end:							; copy scrolled sprite from sprite buffer to actual buffer to required x_pos
													; calculate address based on x_pos
				MIW	Buffer-4 _enemy2_pos_pointer						; top position y=0 
				MBZ _enemy2_y_top Z3	INZ Z3
			e2_multipl_loop:	DEZ Z3	BEQ e2_multipl_exit				; populate _enemy_pos_pointer by multiplying y coord by 64 
								AIW 64	_enemy2_pos_pointer		JPA e2_multipl_loop
			e2_multipl_exit:
				ABW _enemy2_x_pos 	_enemy2_pos_pointer
				MIW Buffer-1600 	_enemy2_buffer_pointer
				MBZ _enemy2_sprite_height Z7		; poputalting sprite height
			e2_loop3:								; outer loop (22 lines high) 
					MIZ 4 Z6						; populating sprite width in bytes (whole buffer is 4 bytes) 
			e2_loop4:								; inner loop (3 bytes in a row)
					LDR _enemy2_buffer_pointer 	ORR _enemy2_pos_pointer	STR _enemy2_pos_pointer		; actual byte copy
					INW _enemy2_buffer_pointer 	INW _enemy2_pos_pointer
					DEZ Z6 		BNE e2_loop4		; decr counter and repeat if not zero
					AIW 60 _enemy2_pos_pointer	AIW 60 _enemy2_buffer_pointer
					DEZ Z7	BNE e2_loop3			; decr counter and go to next line if not zero 
			RTS
	enemy2_run_ends:	
		JPS _Random ANI 0x1f STB _enemy2_countdown			; repopulate countdown
		INB _enemy2_countdown								; prevent zero
	enemy2_exit:	
		RTS

_enemy2_countdown:		0
_enemy2_x_pos:			0
_enemy2_scroll:			0
_enemy2_sprite_pointer:	0x0000	; this is a variable which is modified during sprite copy 
_enemy2_tmp_pointer:	0x0000 	; pointer to a pointer
_enemy2_pos_pointer:	0x0000	; this is a variable which is modified during sprite copy 
_enemy2_sprite_height:	0
_enemy2_sprite_width:	0
_enemy2_y_top:			0 		; for collision detection
_enemy2_y_bottom:		0		; for collision detection
_enemy2_buffer_pointer:	0x0000	; buffer for sprite scrolling at Buffer-1600	
_enemy2_index:			0		; index of currently running enemy , to be randomized each enemy starts its run

Clear_sprite_buffer:	; clears teporary sprite buffer before usage
		CLL Buffer-1600	CLL Buffer-1536	CLL Buffer-1472	CLL Buffer-1408	CLL Buffer-1344
		CLL Buffer-1280	CLL Buffer-1216	CLL Buffer-1152	CLL Buffer-1088	CLL Buffer-1024
		CLL Buffer-960	CLL Buffer-896	CLL Buffer-832	CLL Buffer-768	CLL Buffer-704
		CLL Buffer-640	CLL Buffer-576	CLL Buffer-512	CLL Buffer-448	CLL Buffer-384
		CLL Buffer-320	CLL Buffer-256	CLL Buffer-192	CLL Buffer-128	CLL Buffer-64
		RTS
Scroll_sprite_buffer:	; logical shift left one bit (effectively scrolls the gfx right
		LLL Buffer-1600	LLL Buffer-1536	LLL Buffer-1472	LLL Buffer-1408	LLL Buffer-1344
		LLL Buffer-1280	LLL Buffer-1216	LLL Buffer-1152	LLL Buffer-1088	LLL Buffer-1024
		LLL Buffer-960	LLL Buffer-896	LLL Buffer-832	LLL Buffer-768	LLL Buffer-704
		LLL Buffer-640	LLL Buffer-576	LLL Buffer-512	LLL Buffer-448	LLL Buffer-384
		LLL Buffer-320	LLL Buffer-256	LLL Buffer-192	LLL Buffer-128	LLL Buffer-64
		RTS

				;******************
Draw_Moon:		;* Fully self sufficient moon handling procedure
				;* scrolls moon sprite across the screen at constant height
				;* with a speed given in _moon_speed [in frames per pixel] 
				;******************
		MIW Moon 		_moon_sprite_pointer	
		MBB _moon_master_pos_pointer 	_moon_pos_pointer
		MBB _moon_master_pos_pointer+1 	_moon_pos_pointer+1
		LDB _moon_x_bytes		ADW _moon_pos_pointer 
		MIZ 11 Z7								; populating sprite height in lines 
		dm_loop1:								; outer loop (11 lines high) 
			MIZ 2 Z6							; populating sprite width in bytes 
			dm_loop2:							; inner loop (2 bytes in a row)
				LDR _moon_sprite_pointer 		; byte copy
				STR _moon_pos_pointer			; 
				INW _moon_sprite_pointer 
				INW _moon_pos_pointer
				DEZ Z6 			BNE dm_loop2	; decr counter and repeat if not zero
			AIW 62+64 _moon_pos_pointer			; skip 64-2  bytes + one whole line
			DEZ Z7	BNE dm_loop1				; decr counter and go to next line if not zero 
	scroll_moon: 
			MIZ 11 Z7	
			MBB _moon_master_pos_pointer 	_moon_pos_pointer
			MBB _moon_master_pos_pointer+1 	_moon_pos_pointer+1
			LDB _moon_x_bytes		ADW _moon_pos_pointer 
			MIW lll1+1 smcl1+3	MIW lll1+2 smcl2+3			; prepares self modifying loop
	smcl1:	MBB _moon_pos_pointer 	lll1+1					; sml updating another sml
	smcl2:	MBB _moon_pos_pointer+1 lll1+2
			AIW 128 _moon_pos_pointer						; update self modifying loop
			AIW 3 smcl1+3
			AIW 3 smcl2+3
			DEZ Z7 	BNE smcl1								; loop 11 times
			DEB _moon_scroll_counter	BNE scroll_moon_by	; check the counter ot see if its time to progress
			MBB _moon_speed _moon_scroll_counter			; reset counter to given speed
			DEB _scroll_moon_by		BNE scroll_moon_by
			MIB 8 _scroll_moon_by
			DEB _moon_x_bytes 		BNE scroll_moon_exit	
			MIB 40 _moon_x_bytes							; reached beginning of a screen, loop the moon again 40 bytes to the right
			JPA scroll_moon_exit
	scroll_moon_by:
			MBZ _scroll_moon_by Z4
	moon_scroll_loop:
			LDZ Z4 CPI 0 BEQ scroll_moon_exit
	lll1:	LLL 0x0000	LLL 0x0000	LLL 0x0000	LLL 0x0000	LLL 0x0000	
			LLL 0x0000	LLL 0x0000	LLL 0x0000	LLL 0x0000	LLL 0x0000
			LLL 0x0000
			DEZ Z4
			JPA moon_scroll_loop
	scroll_moon_exit:
			RTS

_moon_scroll_counter:		1
_scroll_moon_by:			8
_moon_sprite_pointer:		0x0000
_moon_pos_pointer:			0x0000
_moon_master_pos_pointer:	Buffer+315
_moon_x_bytes:				35
_moon_speed: 				14								; initial speed /frames per pixel

				;******************
Draw_Cloud:		;* Fully self sufficient cloud handling procedure
				;* scrolls cloud sprite across the screen at constant height
				;* with a speed given in _cloud_speed [in frames per pixel] 
				;******************
		MIW Cloud 	_cloud_sprite_pointer	
		MBB _cloud_master_pos_pointer 	_cloud_pos_pointer
		MBB _cloud_master_pos_pointer+1 	_cloud_pos_pointer+1
		LDB _cloud_x_bytes		ADW _cloud_pos_pointer 
		MIZ 5 Z7								; populating sprite height in lines 
		dc_loop1:								; outer loop (11 lines high) 
			MIZ 3 Z6							; populating sprite width in bytes 
			dc_loop2:							; inner loop (2 bytes in a row)
				LDR _cloud_sprite_pointer 		; byte copy
				STR _cloud_pos_pointer			; 
				INW _cloud_sprite_pointer 
				INW _cloud_pos_pointer
				DEZ Z6 			BNE dc_loop2	; decr counter and repeat if not zero
			AIW 61+64 _cloud_pos_pointer		; skip 64-3  bytes + one whole line
			DEZ Z7	BNE dc_loop1				; decr counter and go to next line if not zero 
	scroll_cloud: 
			MIZ 5 Z7	
			MBB _cloud_master_pos_pointer 	_cloud_pos_pointer
			MBB _cloud_master_pos_pointer+1 	_cloud_pos_pointer+1
			LDB _cloud_x_bytes		ADW _cloud_pos_pointer 
			MIW lll2+1 sccl1+3	MIW lll2+2 sccl2+3			; prepares self modifying loop
	sccl1:	MBB _cloud_pos_pointer 	lll2+1					; sml updating another sml
	sccl2:	MBB _cloud_pos_pointer+1 lll2+2
			AIW 128 _cloud_pos_pointer						; update self modifying loop
			AIW 3 sccl1+3
			AIW 3 sccl2+3
			DEZ Z7 	BNE sccl1								; loop 11 times
			DEB _cloud_scroll_counter	BNE scroll_cloud_by	; check the counter ot see if its time to progress
			MBB _cloud_speed _cloud_scroll_counter			; reset counter to given speed
			DEB _scroll_cloud_by		BNE scroll_cloud_by
			MIB 8 _scroll_cloud_by
			DEB _cloud_x_bytes 		BNE scroll_cloud_exit	
			MIB 40 _cloud_x_bytes							; reached beginning of a screen, loop the moon again 40 bytes to the right
			JPA scroll_cloud_exit
	scroll_cloud_by:
			MBZ _scroll_cloud_by Z4
	cloud_scroll_loop:
			LDZ Z4 CPI 0 BEQ scroll_cloud_exit
	lll2:	LLL 0x0000	LLL 0x0000	LLL 0x0000	LLL 0x0000	LLL 0x0000	LLL 0x0000
			DEZ Z4
			JPA cloud_scroll_loop
	scroll_cloud_exit:
			RTS

_cloud_scroll_counter:		1
_scroll_cloud_by:			8
_cloud_sprite_pointer:		0x0000
_cloud_pos_pointer:			0x0000
_cloud_master_pos_pointer:	Buffer+1019
_cloud_x_bytes:				41
_cloud_speed:		 		4							; initial speed /frames per pixel

				;******************	
Animate_ground:	;* calculete next ground position based on game speed
				;* I may need fractions in game speed, actual game speeds are only between 3 and 6 [pix per frame]
				;* rightnow it's fixed speeds 3,4,5,6 pixels per frame
				;* input: 	_game_speed
				;* output: 	_gnd_pattern_pos, _gnd_scroll 
				;******************
		LDB _game_speed ADB	_gnd_scroll STB _gnd_scroll		; increase scroll by game speed value
		LR3	ADB	_gnd_pattern_pos	STB _gnd_pattern_pos	; shift right 3 bits to evenually increase pattern position also
		LDB _gnd_scroll		ANI 0x07	STB _gnd_scroll		; leave only 3 youngest bits as next scroll value	
		RTS

				;******************
Draw_Ground:	;* Drawing ground pattern every frame 
				;* input: 	_gnd_pattern_pos, _gnd_scroll 
				;* uses data: 	gnd_pattern_msb gnd_pattern_lsb
				;* zero page:	_gnd_tile_ptr	_gnd_screen_ptr	Z3	Z4	Z5
				;******************
		MIW Buffer+4032-64 _gnd_master_ptr			; populate master pointer with constant adress of first ground address
		MIZ 36 Z3									; initiate loop (playfield is 36 bytes wide) 
		MBZ _gnd_pattern_pos Z4						; Z4 will be indexing ground pattern (0-255)

				MIB 0 _gnd_scroll_offset			; multiplication loop 
				MBZ _gnd_scroll Z5					; add (scroll*6) to _gnd_tile_ptr
	dg_multipl:	LDZ Z5 	CPI 0 	BEQ dg_multipl_exit
				AIB 5 _gnd_scroll_offset
				DEZ Z5
				JPA dg_multipl	
	dg_multipl_exit:								; now _scroll_offset = _gnd_scroll*5				

dg_loop:
			MBZ _gnd_master_ptr _gnd_screen_ptr			; populate ZP dest pointer
			MBZ _gnd_master_ptr+1 _gnd_screen_ptr+1
			LZB Z4 gnd_pattern_lsb 	STZ _gnd_tile_ptr	; populate ZP src pointer	
			LZB Z4 gnd_pattern_msb 	STZ _gnd_tile_ptr+1
			LDB _gnd_scroll_offset	ADV _gnd_tile_ptr	; move pointer to scrolled tile (by offset of bytes)
	dg_copy:	LDT	_gnd_tile_ptr	STT _gnd_screen_ptr		INZ _gnd_tile_ptr	AIV 64 _gnd_screen_ptr	
				LDT	_gnd_tile_ptr	STT _gnd_screen_ptr		INZ _gnd_tile_ptr	AIV 64 _gnd_screen_ptr	
				LDT	_gnd_tile_ptr	STT _gnd_screen_ptr		INZ _gnd_tile_ptr	AIV 64 _gnd_screen_ptr	
				LDT	_gnd_tile_ptr	STT _gnd_screen_ptr		INZ _gnd_tile_ptr	AIV 64 _gnd_screen_ptr	
				LDT	_gnd_tile_ptr	STT _gnd_screen_ptr		INZ _gnd_tile_ptr	AIV 64 _gnd_screen_ptr	
			INW _gnd_master_ptr
			INZ Z4
			DEZ Z3	 BNE dg_loop
		RTS

_gnd_master_ptr:	0x0000		
_gnd_pattern_pos:	0
_gnd_scroll:		0			; can be between 0..7
_gnd_scroll_offset:	0			; will be calculated as _gnd_scroll*5
_game_speed:		3			; game speeed parameter , in real sceanario between [3..6]
_game_level:		0			; game level, starts with 0 level ups after each 100 pts.

					;******************
read_joystick:		;* Joystick handlig routine
					;* check register any key code, if presed set key variable and pressed variable 
					; ******************
				LDB vsync	STB _joy						; read and store regiater 0xfee1
				CLB _up		CLB _down	CLB _pressed
	rj_up:		LDI 0x08 ANB _joy CPI 0x00	BNE rj_fire		MIB 1 _up	MIB 1 _pressed; up
	rj_fire:	LDI 0x10 ANB _joy CPI 0x00	BNE rj_down		MIB 1 _up	MIB 1 _pressed; fire
	rj_down:	LDI 0x04 ANB _joy CPI 0x00	BNE rj_exit		MIB 1 _down	MIB 1 _pressed; down
	rj_exit:	RTS

_joy:		0
_up: 		0
_down: 		0
_pressed:  	0
	
				; ******************
wait_frames:	; * waiting 'A' number of frames
				; ******************
				STB wf_counter                  ; remember A 
	wf_loop:	LDB wf_counter  
				CPI 0   BEQ wf_end              ; check if counter = 0
				JPS waitVsync                   ; wait one frame
				DEB wf_counter  JPA wf_loop     ; dec counter, loop again
	wf_end:     RTS
wf_counter: 0

				; ******************
waitVsync:  	; * waiting for VSync; 
				; * routine copied directly from GitHub hans61
				; ******************
				LDB vsync	ANI 0x40	CPI 0x00	BEQ waitVsync   ; wait until high
	vsync1:     LDB vsync	ANI 0x40	CPI 0x00	BNE vsync1      ; now wait till end of signal
				RTS

;   *************************************
;   *** Data section                  ***
;   *************************************
#page
dino_jump_y_coords:		; 45 normal dino running y coordinate 
						; 0  top of playfield cordinate
	41	36	32	28	24	21	17	15	12	10	7	6	4	3	2	1	0	0 	0 	0	0	1	2	3	4	6	7	10	12	15	17	21	24	28	32	36	41	45	0xFF 0xff
						; enemies data tables (index to be randomized each enemy starts its run)
enemies_ptr_lsb:	<Ptero_ptr	<Ptero_ptr	<Ptero_ptr	<Ptero_ptr	<Cactb1_ptr	<Cactb2_ptr	<Cacts1_ptr	<Cacts2_ptr	<Cacts3_ptr	<Cacts1_ptr	<Cactb1_ptr	<Cactb2_ptr	<Cacts1_ptr	<Cacts2_ptr	<Cacts3_ptr	<Cacts1_ptr										
enemies_ptr_msb:	>Ptero_ptr	>Ptero_ptr	>Ptero_ptr	>Ptero_ptr	>Cactb1_ptr	>Cactb2_ptr	>Cacts1_ptr	>Cacts2_ptr	>Cacts3_ptr	>Cacts1_ptr	>Cactb1_ptr	>Cactb2_ptr	>Cacts1_ptr	>Cacts2_ptr	>Cacts3_ptr	>Cacts1_ptr										
enemies_height:		18			18			18			18			24			24			17			17			17			17			24			24			17			17			17			17										
enemies_width:		3			3			3			3			2			4			2			3			4			2			2			4			2			3			4			2										
enemies_y_top:		12			32			45			32			67-24		67-24		67-17		67-17		67-17		67-17		67-24		67-24		67-17		67-17		67-17		67-17										
enemies_y_bottom:	12+18		32+18		45+18		32+18		67			67			67			67			67			67			67			67			67			67			67			67	

;   *************************************
;   *** Sprite pointers               ***
;   *************************************
Dino_runs_ptr:  	Dino_runs1	
Dino_still_ptr:		Dino_still
Dino_ducks_ptr:		Dino_ducks1
Dino_dead_ptr: 		Dino_dead
Ptero_ptr:			Ptero1
Cacts1_ptr:			Cactus_small1
Cacts2_ptr:			Cactus_small2
Cacts3_ptr:			Cactus_small3
Cactb1_ptr:			Cactus_big1
Cactb2_ptr:			Cactus_big2

;   *************************************
;   *** Sprites                       ***
;   *************************************
Dino_still:	;		3 bytes x 22 lines
	0x00	0xF0	0x0F	0x00	0xF8	0x1F	0x00	0xD8	0x1F	0x00	0xF8	0x1F
	0x00	0xF8	0x1F	0x00	0xF8	0x1F	0x00	0xF8	0x00	0x00	0xF8	0x07
	0x02	0x7C	0x00	0x02	0x7E	0x00	0x86	0xFF	0x01	0xCE	0x7F	0x01
	0xFE	0x7F	0x00	0xFE	0x7F	0x00	0xFC	0x3F	0x00	0xF8	0x3F	0x00
	0xF0	0x1F	0x00	0xE0	0x0F	0x00	0xC0	0x0D	0x00	0xC0	0x08	0x00
	0x40	0x08	0x00	0xC0	0x18	0x00	; now outline
	0xE7	0xCF	0xCF	0xCD	0xCF	0xC8	0x4F	0xCA	0xCF	0x98
Dino_runs1:	;		3 bytes x 22 lines
	0x00	0xF0	0x0F	0x00	0xF8	0x1F	0x00	0xD8	0x1F	0x00	0xF8	0x1F	
	0x00	0xF8	0x1F	0x00	0xF8	0x1F	0x00	0xF8	0x00	0x00	0xF8	0x07
	0x02	0x7C	0x00	0x02	0x7E	0x00	0x86	0xFF	0x01	0xCE	0x7F	0x01
	0xFE	0x7F	0x00	0xFE	0x7F	0x00	0xFC	0x3F	0x00	0xF8	0x3F	0x00
	0xF0	0x1F	0x00	0xE0	0x0F	0x00	0xC0	0x0C	0x00	0x80	0x09	0x00
	0x00	0x08	0x00	0x00	0x18	0x00	; now outline
	0xE7	0xCF	0xCF	0xCC	0x9F	0xC9	0x3F	0xC8	0xFF	0x99
Dino_runs2:	;		3 bytes x 22 lines
	0x00	0xF0	0x0F	0x00	0xF8	0x1F	0x00	0xD8	0x1F	0x00	0xF8	0x1F
	0x00	0xF8	0x1F	0x00	0xF8	0x1F	0x00	0xF8	0x00	0x00	0xF8	0x07
	0x02	0x7C	0x00	0x02	0x7E	0x00	0x86	0xFF	0x01	0xCE	0x7F	0x01
	0xFE	0x7F	0x00	0xFE	0x7F	0x00	0xFC	0x3F	0x00	0xF8	0x3F	0x00
	0xF0	0x1F	0x00	0xE0	0x0F	0x00	0xC0	0x19	0x00	0xC0	0x00	0x00
	0x40	0x00	0x00	0xC0	0x00	0x00	; now outline
	0xE7	0x8F	0xCF	0x99	0xCF	0xC0	0x4F	0xFE	0xCF	0xFC
Dino_dead:	;		3 bytes x 22 lines
	0x00	0xF0	0x0F	0x00	0x88	0x1F	0x00	0xA8	0x1F	0x00	0x88	0x1F
	0x00	0xF8	0x1F	0x00	0xF8	0x1F	0x00	0xF8	0x1F	0x00	0xF8	0x07
	0x02	0x7C	0x00	0x02	0x7E	0x00	0x86	0xFF	0x01	0xCE	0x7F	0x01
	0xFE	0x7F	0x00	0xFE	0x7F	0x00	0xFC	0x3F	0x00	0xF8	0x3F	0x00
	0xF0	0x1F	0x00	0xE0	0x0F	0x00	0xC0	0x0D	0x00	0xC0	0x08	0x00
	0x40	0x08	0x00	0xC0	0x18	0x00	; now outline
	0xE7	0xCF	0xCF	0xCD	0xCF	0xC8	0x4F	0xCA	0xCF	0x98	
Dino_ducks1:	;	4 bytes x 13 lines	
	0x02	0x00	0xF8	0x07	0x8E	0xFF	0xFC	0x0F	0xFE	0xFF	0xEF	0x0F
	0xFC	0xFF	0xFF	0x0F	0xF8	0xFF	0xFF	0x0F	0xF0	0xFF	0xFF	0x0F
	0xE0	0xFF	0x7F	0x00	0xC0	0xFF	0xF9	0x03	0x80	0x4F	0x00	0x00
	0xC0	0xDD	0x00	0x00	0xC0	0x00	0x00	0x00	0x40	0x00	0x00	0x00
	0xC0	0x00	0x00	0x00	; now outline
	0x8F	0x4F	0x00	0xCF	0xDD	0xFC	0xCF	0x00	0xFC	0x4F	0xFC	0xFF
	0xCF	0xFC	0xFF
Dino_ducks2:	;	4 bytes x 13 lines
	0x02	0x00	0xF8	0x07	0x8E	0xFF	0xFC	0x0F	0xFE	0xFF	0xEF	0x0F
	0xFC	0xFF	0xFF	0x0F	0xF8	0xFF	0xFF	0x0F	0xF0	0xFF	0xFF	0x0F
	0xE0	0xFF	0x7F	0x00	0xC0	0xFF	0xF9	0x03	0x80	0x5F	0x00	0x00
	0x40	0xCE	0x00	0x00	0xC0	0x06	0x00	0x00	0x00	0x02	0x00	0x00
	0x00	0x06	0x00	0x00	; now outline
	0x8F	0x5F	0x00	0x4F	0xCE	0xFC	0xCF	0x06	0xFC	0x0F	0xE2	0xFF
	0x7F	0xE6	0xFF
Ptero1:		; 3 bytes x 18 lines
	0x00	0x00	0x00	0x00	0x00	0x00	0x00	0x00	0x00	0x60	0x00	0x00
	0x70	0x00	0x00	0xF8	0x00	0x00	0xFC	0x00	0x00	0xFE	0x7F	0x00
	0x80	0xFF	0x00	0x00	0xFF	0x3F	0x00	0xFE	0x07	0x00	0xFE	0x1F
	0x00	0xFE	0x03	0x00	0x1E	0x00	0x00	0x0E	0x00	0x00	0x06	0x00
	0x00	0x06	0x00 	0x00	0x02	0x00
Ptero2:		; 3 bytes x 18 lines
	0x00	0x01	0x00 	0x00	0x03	0x00	0x00	0x07	0x00	0x60	0x0E	0x00
	0x70	0x1E	0x00	0xF8	0x3E	0x00	0xFC	0x7E	0x00	0xFE	0x7F	0x00
	0x80	0xFF	0x00	0x00	0xFF	0x3F	0x00	0xFE	0x07	0x00	0xFC	0x1F
	0x00	0xF8	0x03	0x00	0x00	0x00	0x00	0x00	0x00	0x00	0x00	0x00
	0x00	0x00	0x00	0x00	0x00	0x00
Moon: 		; 2 bytes x 22 lines (11 lines as every second line is blank)
	0x1A	0x00	0xB0	0x01	0xA0	0x05	0x60	0x0D	0xC0	0x1A	0x40	0x15
	0xC0	0x1A	0x60	0x0D	0xA0	0x05	0xB0	0x01	0x1A	0x00	
Cloud:		; 3 bytes x 6 lines (every second line is blank)
	0x00	0x8C	0x02	0x80	0x65	0x1A	0x58	0xCA	0x64	0x16	0x53	0xD2	0x5B	0x85	0x55
Cactus_small3:	; 4 bytes x 17 lines (3 small cactuses) 
	0x18	0x00	0x30	0x00	0x18	0x00	0x36	0x00	0xD8	0x30	0xB6	0x01	0xD8	0x36	0xB6	0x01
	0xDB	0x36	0xB6	0x01	0xDB	0x36	0xBE	0x01	0xDB	0xB6	0xFD	0x01	0xFB	0xB6	0xF1	0x00
	0x7B	0xB6	0x31	0x00	0x1F	0xB6	0x31	0x00	0x1E	0xBC	0x31	0x00	0x18	0xFC	0x31	0x00
	0x18	0xF0	0x30	0x00	0x18	0x30	0x30	0x00	0x18	0x30	0x30	0x00	0x18	0x30	0x30	0x00
	0x18	0x30	0x30	0x00
Cactus_small2:	; 3 bytes x 17 lines (2 small cactuses) 
	0x18	0x30	0x00	0x18	0xB0	0x01	0x1B	0xB0	0x01	0xDB	0xB0	0x01	0xDB	0xB6	0x01
	0xDB	0xB6	0x01	0xDB	0xB6	0x01	0xDB	0xF6	0x01	0xDF	0xF6	0x00	0xDE	0x3E	0x00
	0xF8	0x3C	0x00	0x78	0x30	0x00	0x18	0x30	0x00	0x18	0x30	0x00	0x18	0x30	0x00
	0x18	0x30	0x00	0x18	0x30	0x00
Cactus_small1:	; 2 byteS x 17 lines (1 small cactus)
	0x38	0x00	0xB8	0x01	0xB8	0x01	0xBB	0x01	0xBB	0x01	0xBB	0x01	0xFB	0x01	0xFB	0x00
	0x3F	0x00	0x3E	0x00	0x38	0x00	0x38	0x00	0x38	0x00	0x38	0x00	0x38	0x00	0x38	0x00
	0x38	0x00
Cactus_big2:	; 4 bytes x 24 lines (2 big cactuses)
	0x60	0x00	0x0C	0x00	0xF0	0x40	0x1E	0x00	0xF0	0xE0	0x9E	0x00	0xF2	0xE0	0xDE	0x01
	0xF7	0xE0	0xDE	0x01	0xF7	0xE0	0xDE	0x01	0xF7	0xE4	0xDE	0x01	0xF7	0xEE	0xDE	0x01
	0xF7	0xEE	0xDE	0x01	0xF7	0xEE	0xDE	0x01	0xF7	0xEE	0xDF	0x01	0xF7	0xCE	0xDF	0x01
	0xFF	0x8E	0xFF	0x01	0xFE	0x0E	0xFE	0x00	0xFC	0x0F	0x7E	0x00	0xF0	0x07	0x1E	0x00
	0xF0	0x03	0x1E	0x00	0xF0	0x00	0x1E	0x00	0xF0	0x00	0x1E	0x00	0xF0	0x00	0x1E	0x00
	0xF0	0x00	0x1E	0x00	0xF0	0x00	0x1E	0x00	0xF0	0x00	0x1E	0x00	0xF0	0x00	0x1E	0x00
Cactus_big1:	; 2 bytes x 24 lines (1 big cactus)
	0xC0	0x00	0xE0	0x01	0xE0	0x01	0xE0	0x11	0xE0	0x39	0xE0	0x39	0xE2	0x39	0xE7	0x39
	0xE7	0x39	0xE7	0x39	0xE7	0x39	0xE7	0x3F	0xE7	0x1F	0xE7	0x0F	0xE7	0x01	0xFF	0x01
	0xFE	0x01	0xFC	0x01	0xE0	0x01	0xE0	0x01	0xE0	0x01	0xE0	0x01	0xE0	0x01	0xE0	0x01
			; Ground graphic data. 
			; Each tile in 8 versions representing different scroll levels, this is to avoid costly bit shifting on the fly 
			; 5 bytes per tile (8 scroll versions) = 40 bytes
#page		; prevents indexing copy glitches
A1:	0x00	0xFF	0x00	0x00	0x00		0x00	0xFF	0x00	0x00	0x00		0x80	0x7F	0x00	0x80	0x00		0xC0	0x3F	0x00	0xC0	0x00		0xE0	0x1F	0x00	0x60	0x00		0xF0	0x0F	0x00	0x30	0x00		0x78	0x87	0x00	0x18	0x00		0x3C	0xC3	0x00	0x0C	0x00															
A2:	0x1E	0xE1	0x00	0x06	0x80		0x0F	0xF0	0x00	0x03	0x40		0x07	0xF8	0x00	0x01	0x20		0x03	0xFC	0x00	0x00	0x10		0x01	0xFE	0x00	0x00	0x88		0x00	0xFF	0x00	0x00	0xC4		0x00	0xFF	0x00	0x00	0x62		0x00	0xFF	0x00	0x00	0x31																
A3:	0x00	0xFF	0x00	0x00	0x18		0x00	0x7F	0x80	0x00	0x0C		0x00	0x3F	0xC0	0x00	0x06		0x00	0x1F	0x60	0x80	0x03		0x00	0x0F	0x30	0xC0	0x01		0x00	0x07	0x18	0xE0	0x00		0x00	0x03	0x8C	0x70	0x00		0x00	0x01	0xC6	0x38	0x00																
A4:	0x00	0x80	0x63	0x1C	0x80		0x00	0xC0	0x31	0x0E	0x40		0x00	0xE0	0x18	0x07	0x20		0x00	0xF0	0x0C	0x03	0x10		0x00	0xF8	0x06	0x01	0x08		0x00	0xFC	0x03	0x00	0x04		0x00	0xFE	0x01	0x00	0x02		0x00	0xFF	0x00	0x00	0x01																
#page		; prevents indexing copy glitches
B1:	0x00	0xFF	0x00	0x00	0x00		0x00	0xFF	0x00	0x00	0x00		0x00	0xFF	0x00	0x00	0x00		0x00	0xFF	0x00	0x00	0x00		0x00	0xFF	0x00	0x00	0x00		0x00	0xFF	0x00	0x00	0x00		0x00	0xFF	0x00	0x80	0x00		0x00	0xFF	0x00	0xC0	0x00																	
B2:	0x00	0xFF	0x00	0x60	0x00		0x00	0xFF	0x00	0x30	0x00		0x00	0xFF	0x00	0x18	0x00		0x00	0xFF	0x00	0x0C	0x00		0x00	0xFF	0x00	0x06	0x00		0x00	0xFF	0x00	0x03	0x00		0x00	0xFF	0x00	0x01	0x00		0x00	0xFF	0x00	0x00	0x00																	
B3:	0x00	0xFF	0x00	0x00	0x00		0x00	0xFF	0x00	0x00	0x80		0x00	0xFF	0x00	0x00	0xC0		0x00	0xFF	0x00	0x00	0x60		0x00	0xFF	0x00	0x00	0x30		0x00	0xFF	0x00	0x00	0x18		0x00	0xFF	0x00	0x80	0x0C		0x00	0xFF	0x00	0x40	0x06																	
B4:	0x00	0xFF	0x00	0x20	0x03		0x00	0xFF	0x00	0x10	0x01		0x00	0xFF	0x00	0x08	0x00		0x00	0xFF	0x00	0x04	0x00		0x00	0xFF	0x00	0x02	0x00		0x00	0xFF	0x00	0x01	0x00		0x00	0xFF	0x00	0x00	0x00		0x00	0xFF	0x00	0x00	0x00																	
#page		; prevents indexing copy glitches	
C1:	0x00	0xFF	0x00	0x00	0x00		0x00	0xFF	0x00	0x00	0x80		0x00	0xFF	0x00	0x00	0xC0		0x00	0xFF	0x00	0x00	0x60		0x00	0xFF	0x00	0x00	0x30		0x00	0xFF	0x00	0x00	0x18		0x00	0xFF	0x00	0x00	0x0C		0x00	0xFF	0x00	0x00	0x06																	
C2:	0x00	0xFF	0x00	0x00	0x03		0x00	0xFF	0x00	0x80	0x01		0x00	0xFF	0x00	0x40	0x00		0x00	0xFF	0x00	0x20	0x00		0x00	0xFF	0x00	0x10	0x00		0x00	0xFF	0x00	0x08	0x00		0x00	0xFF	0x00	0x04	0x00		0x00	0xFF	0x00	0x02	0x00																	
C3:	0x00	0xFF	0x00	0x01	0x00		0x00	0xFF	0x00	0x00	0x00		0x00	0xFF	0x00	0x00	0x00		0x00	0xFF	0x00	0x00	0x00		0x00	0xFF	0x00	0x00	0x00		0x00	0xFF	0x00	0x00	0x00		0x00	0xFF	0x00	0x00	0x00		0x00	0xFF	0x00	0x00	0x00																	
C4:	0x00	0xFF	0x00	0x00	0x80		0x00	0xFF	0x00	0x00	0x40		0x00	0xFF	0x00	0x00	0x20		0x00	0xFF	0x00	0x00	0x10		0x00	0xFF	0x00	0x00	0x08		0x00	0xFF	0x00	0x00	0x04		0x00	0xFF	0x00	0x00	0x02		0x00	0xFF	0x00	0x00	0x01																	
#page		; prevents indexing copy glitches
D1:	0x00	0xFF	0x00	0x00	0x00		0x00	0xFF	0x00	0x00	0x80		0x00	0xFF	0x00	0x00	0x40		0x00	0xFF	0x00	0x00	0x20		0x00	0xFF	0x00	0x00	0x10		0x00	0xFF	0x00	0x00	0x08		0x00	0xFF	0x00	0x00	0x04		0x00	0xFF	0x00	0x00	0x02																			
D2:	0x00	0xFF	0x00	0x00	0x01		0x00	0xFF	0x00	0x00	0x00		0x00	0xFF	0x00	0x00	0x00		0x00	0xFF	0x00	0x00	0x00		0x00	0xFF	0x00	0x00	0x00		0x00	0xFF	0x00	0x00	0x00		0x00	0xFF	0x00	0x00	0x00		0x00	0xFF	0x00	0x00	0x00																			
D3:	0x00	0xFF	0x00	0x00	0x00		0x00	0xFF	0x00	0x00	0x00		0x00	0xFF	0x00	0x00	0x00		0x00	0xFF	0x00	0x00	0x00		0x00	0xFF	0x00	0x00	0x00		0x00	0xFF	0x00	0x00	0x00		0x00	0xFF	0x00	0x00	0x00		0x00	0xFF	0x00	0x80	0x00																			
D4:	0x00	0xFF	0x00	0xC0	0x00		0x00	0xFF	0x00	0x60	0x00		0x00	0xFF	0x00	0x30	0x00		0x00	0xFF	0x00	0x18	0x00		0x00	0xFF	0x00	0x0C	0x00		0x00	0xFF	0x00	0x06	0x00		0x00	0xFF	0x00	0x03	0x00		0x00	0xFF	0x00	0x01	0x00																			

#page
gnd_pattern_lsb:	; LSBs for ground pattern (256 bytes)
	<C1 <C2 <C3 <C4 	<D1 <D2 <D3 <D4 	<C1 <C2 <C3 <C4 	<D1 <D2 <D3 <D4 	<B1 <B2 <B3 <B4 	<D1 <D2 <D3 <D4 	<B1 <B2 <B3 <B4 	<D1 <D2 <D3 <D4
 	<B1 <B2 <B3 <B4 	<B1 <B2 <B3 <B4 	<C1 <C2 <C3 <C4 	<B1 <B2 <B3 <B4 	<B1 <B2 <B3 <B4		<C1 <C2 <C3 <C4 	<B1 <B2 <B3 <B4 	<D1 <D2 <D3 <D4
 	<D1 <D2 <D3 <D4 	<B1 <B2 <B3 <B4 	<D1 <D2 <D3 <D4 	<C1 <C2 <C3 <C4 	<A1 <A2 <A3 <A4  	<B1 <B2 <B3 <B4 	<C1 <C2 <C3 <C4 	<D1 <D2 <D3 <D4
 	<D1 <D2 <D3 <D4 	<C1 <C2 <C3 <C4 	<B1 <B2 <B3 <B4 	<C1 <C2 <C3 <C4 	<B1 <B2 <B3 <B4 	<C1 <C2 <C3 <C4 	<C1 <C2 <C3 <C4 	<C1 <C2 <C3 <C4
 	<D1 <D2 <D3 <D4 	<C1 <C2 <C3 <C4 	<B1 <B2 <B3 <B4 	<D1 <D2 <D3 <D4 	<C1 <C2 <C3 <C4 	<C1 <C2 <C3 <C4 	<B1 <B2 <B3 <B4 	<D1 <D2 <D3 <D4
 	<B1 <B2 <B3 <B4 	<C1 <C2 <C3 <C4 	<D1 <D2 <D3 <D4 	<D1 <D2 <D3 <D4 	<C1 <C2 <C3 <C4 	<B1 <B2 <B3 <B4 	<C1 <C2 <C3 <C4 	<B1 <B2 <B3 <B4
 	<D1 <D2 <D3 <D4 	<B1 <B2 <B3 <B4 	<C1 <C2 <C3 <C4 	<D1 <D2 <D3 <D4 	<C1 <C2 <C3 <C4 	<A1 <A2 <A3 <A4 	<D1 <D2 <D3 <D4 	<D1 <D2 <D3 <D4
 	<B1 <B2 <B3 <B4 	<C1 <C2 <C3 <C4 	<C1 <C2 <C3 <C4 	<B1 <B2 <B3 <B4 	<D1 <D2 <D3 <D4 	<D1 <D2 <D3 <D4 	<C1 <C2 <C3 <C4 	<B1 <B2 <B3 <B4

gnd_pattern_msb:	; MSBs for ground pattern (256 bytes)
	>C1 >C2 >C3 >C4 	>D1 >D2 >D3 >D4 	>C1 >C2 >C3 >C4 	>D1 >D2 >D3 >D4 	>B1 >B2 >B3 >B4 	>D1 >D2 >D3 >D4 	>B1 >B2 >B3 >B4 	>D1 >D2 >D3 >D4
 	>B1 >B2 >B3 >B4 	>B1 >B2 >B3 >B4 	>C1 >C2 >C3 >C4 	>B1 >B2 >B3 >B4 	>B1 >B2 >B3 >B4 	>C1 >C2 >C3 >C4 	>B1 >B2 >B3 >B4 	>D1 >D2 >D3 >D4
 	>D1 >D2 >D3 >D4 	>B1 >B2 >B3 >B4 	>D1 >D2 >D3 >D4 	>C1 >C2 >C3 >C4 	>A1 >A2 >A3 >A4 	>B1 >B2 >B3 >B4 	>C1 >C2 >C3 >C4 	>D1 >D2 >D3 >D4
 	>D1 >D2 >D3 >D4 	>C1 >C2 >C3 >C4 	>B1 >B2 >B3 >B4 	>C1 >C2 >C3 >C4 	>B1 >B2 >B3 >B4 	>C1 >C2 >C3 >C4 	>C1 >C2 >C3 >C4 	>C1 >C2 >C3 >C4
 	>D1 >D2 >D3 >D4 	>C1 >C2 >C3 >C4 	>B1 >B2 >B3 >B4 	>D1 >D2 >D3 >D4 	>C1 >C2 >C3 >C4 	>C1 >C2 >C3 >C4 	>B1 >B2 >B3 >B4 	>D1 >D2 >D3 >D4
 	>B1 >B2 >B3 >B4 	>C1 >C2 >C3 >C4 	>D1 >D2 >D3 >D4 	>D1 >D2 >D3 >D4 	>C1 >C2 >C3 >C4 	>B1 >B2 >B3 >B4 	>C1 >C2 >C3 >C4 	>B1 >B2 >B3 >B4
 	>D1 >D2 >D3 >D4 	>B1 >B2 >B3 >B4 	>C1 >C2 >C3 >C4 	>D1 >D2 >D3 >D4 	>C1 >C2 >C3 >C4 	>A1 >A2 >A3 >A4 	>D1 >D2 >D3 >D4 	>D1 >D2 >D3 >D4
 	>B1 >B2 >B3 >B4 	>C1 >C2 >C3 >C4 	>C1 >C2 >C3 >C4 	>B1 >B2 >B3 >B4 	>D1 >D2 >D3 >D4 	>D1 >D2 >D3 >D4 	>C1 >C2 >C3 >C4 	>B1 >B2 >B3 >B4

						; ******************
init_speedcopy:  		; *** initializes speed code for copying game screen buffer to playfield
						; *** this code will reside under 0xbe00 and takes over 12kB but runs in 2.6 ms
						; ******************
		LDI <SpeedCopy	STZ Z8
		LDI >SpeedCopy  STZ Z9
		LDI <Playfield	STZ zp_ptr_D			; populate pointers
        LDI >Playfield	STZ zp_ptr_D+1
		LDI <Buffer 	STZ zp_ptr_S			; populate pointers
        LDI >Buffer		STZ zp_ptr_S+1
		MIZ 67 Z7								; 67 lines to copy
	is_loop1:									; outer loop (69 rows) 
			MIZ 36 Z6							; 36 bytes in one row 
			is_loop2:							; inner loop (36 bytes in a row)
				LDI 0x8b 		STT Z8	INV Z8	; actual code creation MBB
				LDZ zp_ptr_S	STT Z8	INV Z8	; actual code creation
				LDZ zp_ptr_S+1	STT Z8	INV Z8	; actual code creation
				LDZ zp_ptr_D	STT Z8	INV Z8	; actual code creation
				LDZ zp_ptr_D+1	STT Z8	INV Z8	; actual code creation
				INV zp_ptr_S 	INV zp_ptr_D	; increase source and destination pointers
				DEZ Z6 			BNE is_loop2	; decr counter and repeat if not zero
			AIV 28 zp_ptr_D						; skip border - 28 bytes
			AIV 28 zp_ptr_S
			DEZ Z7	BNE is_loop1				; decr counter and go to next line if not zero 
			LDI 0x69	STT Z8					; actual code creation RTS
	RTS

;   *************************************
;   *** MinOS API                     ***
;   *** OS LABELS AND CONSTANTS       ***
;   *************************************
#mute
#org 0xbe00	SpeedCopy:				; over 12kB reserved for speed buffer copy code
#org 0x50d3 Playfield:   			; playfield can be moved upper or lower to increase smoothness, depends of buffer copy time
#org 0x2bd3 Buffer:					; 0x6bd3 ; 0x2bd3

#org 0x0070 Z6:                     ; my added zero page indexes
#org 0x0071 Z7:
#org 0x0072 Z8:
#org 0x0073 Z9:
#org 0x0080 xa: steps: 0xffff       ; zero-page graphics interface (OS_SetPixel, OS_ClearPixel, OS_Line, OS_Rect)
            ya:        0xff
            xb:        0xffff
            yb:        0xff
            dx:        0xffff
            dy:        0xff
            bit:       0xff
            err:       0xffff
#org 0x0080 PtrA:                   ; lokaler pointer (3 bytes) used for FLASH addr and bank
#org 0x0083 PtrB:                   ; lokaler pointer (3 bytes)
#org 0x0086 PtrC:                   ; lokaler pointer (3 bytes)
#org 0x0089 PtrD:                   ; lokaler pointer (3 bytes)
#org 0x008c PtrE:                   ; lokaler pointer (2 bytes)
#org 0x008e PtrF:                   ; lokaler pointer (2 bytes)
#org 0x0090 Z0:                     ; OS zero-page multi-purpose registers
#org 0x0091 Z1:
#org 0x0092 Z2:
#org 0x0093 Z3:
#org 0x0094 Z4:
#org 0x0095 Z5:
#org 0x0096 _gnd_tile_ptr:	 0x0000	; my pointers used for draw_ground
#org 0x0098 _gnd_screen_ptr: 0x0000 ; my pointers used for draw_ground
#org 0x00a0 zp_ptr_S:	0xffff      ; my zero page copy source pointer
#org 0x00a2	zp_ptr_D: 	0xffff		; my zero page copy destination pointer
#org 0x00c0 _XPos:                  ; current VGA cursor col position (x: 0..WIDTH-1)
#org 0x00c1 _YPos:                  ; current VGA cursor row position (y: 0..HEIGHT-1)
#org 0x00c2 _RandomState:           ; 4-byte storage (x, a, b, c) state of the pseudo-random generator
#org 0x00c6 _ReadNum:               ; 3-byte storage for parsed 16-bit number, MSB: 0xf0=invalid, 0x00=valid
#org 0x00c9 _ReadPtr:               ; Zeiger (2 bytes) auf das letzte eingelesene Zeichen (to be reset at startup)
#org 0x00cb                         ; 2 bytes unused
#org 0x00cd _ReadBuffer:            ; WIDTH bytes of OS line input buffer
#org 0x00fe ReadLast:               ; last byte of read buffer
#org 0x00ff SystemReg:              ; Don't use it unless you know what you're doing.
#org 0x4000 VIDEORAM:               ; start of 16KB of VRAM 0x4000..0x7fff
#org 0x430c VIEWPORT:               ; start index of 416x240 pixel viewport (0x4000 + 12*64 + 11)
#org 0x0032 WIDTH:                  ; screen width in characters
#org 0x001e HEIGHT:                 ; screen height in characters
#org 0xf000 _Start:             ;Start vector of the OS in RAM
#org 0xf003 _Prompt:            ;Hands back control to the input prompt
#org 0xf006 _MemMove:           ;Moves memory area (may be overlapping)
#org 0xf009 _Random:            ;Returns a pseudo-random byte (see _RandomState)
#org 0xf00c _ScanPS2:           ;Scans the PS/2 register for new input
#org 0xf00f _ResetPS2:          ;Resets the state of PS/2 SHIFT, ALTGR, CTRL
#org 0xf012 _ReadInput:         ;Reads any input (PS/2 or serial)
#org 0xf015 _WaitInput:         ;Waits for any input (PS/2 or serial)
#org 0xf018 _ReadLine:          ;Reads a command line into _ReadBuffer
#org 0xf01b _SkipSpace:         ;Skips whitespaces (<= 39) in command line
#org 0xf01e _ReadHex:           ;Parses command line input for a HEX value
#org 0xf021 _SerialWait:        ;Waits for a UART transmission to complete
#org 0xf027 _FindFile:          ;Searches for file <name> given by _ReadPtr
#org 0xf02a _LoadFile:          ;Loads a file <name> given by _ReadPtr
#org 0xf02d _SaveFile:          ;Saves data to file <name> defined at _ReadPtr
#org 0xf030 _ClearVRAM:         ;Clears the video RAM including blanking areas
#org 0xf033 _Clear:             ;Clears the visible video RAM (viewport)
#org 0xf036 _ClearRow:          ;Clears the current row from cursor pos onwards
#org 0xf039 _ScrollUp:          ;Scrolls up the viewport by 8 pixels
#org 0xf03c _ScrollDn:          ;Scrolls down the viewport by 8 pixels
#org 0xf03f _Char:              ;Outputs a char at the cursor pos (non-advancing)
#org 0xf042 _PrintChar:         ;Prints a char at the cursor pos (advancing)
#org 0xf045 _Print:             ;Prints a zero-terminated immediate string
#org 0xf048 _PrintPtr:          ;Prints a zero-terminated string at an address
#org 0xf04b _PrintHex:          ;Prints a HEX number (advancing)
#org 0xf04e _SetPixel:          ;Sets a pixel at position (x, y)
#org 0xf024 _SerialPrint:       ;Transmits a zero-terminated string via UART
#org 0xf051 _Line:              ;Draws a line using Bresenham’s algorithm
#org 0xf054 _Rect:              ;Draws a rectangle at (x, y) of size (w, h)
#org 0xf057 _ClearPixel:        ;Clears a pixel at position (x, y)
#org 0xfee0 sn76489: 			; expansion SN76489 data port (4HC574)
#org 0xfee1 vsync: 				; expansion 4HC574 input Kempston, bit6 = vsync
#org 0xfee2 cs1sn: 				; expansion bit 0 = 1 -> /CS = 0 | bit 0 = 0 -> /CS = 1, bit0 = sd-card bit1 = sn76489
#emit