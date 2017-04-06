UpdatePlayerSprite:
	ld a, [PlayerWalkAnimationCounter]
	and a
	jr z, .checkIfTextBoxInFrontOfSprite
	cp $ff
	jr z, .disableSprite
	dec a
	ld [PlayerWalkAnimationCounter], a
	jr .disableSprite
; check if a text box is in front of the sprite by checking if the lower left
; background tile the sprite is standing on is greater than $5F, which is
; the maximum number for map tiles
.checkIfTextBoxInFrontOfSprite
	aCoord 8, 9
	ld [hTilePlayerStandingOn], a
	cp $60
	jr c, .lowerLeftTileIsMapTile
.disableSprite
	ld a, $ff
	ld [PlayerSpriteImageIdx], a
	ret
.lowerLeftTileIsMapTile
	call DetectCollisionBetweenSprites
	ld h, wSpriteStateData1 / $100
	ld a, [wWalkCounter]
	and a
	jr nz, .moving
	ld a, [wPlayerMovingDirection]
; check if down
	bit PLAYER_DIR_BIT_DOWN, a
	jr z, .checkIfUp
	xor a ; ld a, SPRITE_FACING_DOWN
	jr .next
.checkIfUp
	bit PLAYER_DIR_BIT_UP, a
	jr z, .checkIfLeft
	ld a, SPRITE_FACING_UP
	jr .next
.checkIfLeft
	bit PLAYER_DIR_BIT_LEFT, a
	jr z, .checkIfRight
	ld a, SPRITE_FACING_LEFT
	jr .next
.checkIfRight
	bit PLAYER_DIR_BIT_RIGHT, a
	jr z, .notMoving
	ld a, SPRITE_FACING_RIGHT
	jr .next
.notMoving
; zero the animation counters
	xor a
	ld [PlayerIntraAnimFrameCounter], a
	ld [PlayerAnimFrameCounter], a
	jr .calcImageIndex
.next
	ld [PlayerFacingDirection], a
	ld a, [wFontLoaded]
	bit 0, a
	jr nz, .notMoving
.moving
	ld a, [wd736]
	bit 7, a ; is the player sprite spinning due to a spin tile?
	jr nz, .skipSpriteAnim
	ld a, [H_CURRENTSPRITEOFFSET]
	add $7
	ld l, a
	ld a, [hl] ; $c1x7 (IntraAnimFrameCounter)
	inc a
	ld [hl], a ; $c1x7 (IntraAnimFrameCounter)
	cp 4
	jr nz, .calcImageIndex
	xor a
	ld [hl], a ; $c1x7 (IntraAnimFrameCounter) = 0
	inc hl
	ld a, [hl] ; $c1x8 (AnimFrameCounter)
	inc a
	and $3
	ld [hl], a ; $c1x8 (AnimFrameCounter)
.calcImageIndex
	ld a, [PlayerAnimFrameCounter]
	ld b, a
	ld a, [PlayerFacingDirection]
	add b
	ld [PlayerSpriteImageIdx], a
.skipSpriteAnim
; If the player is standing on a grass tile, make the player's sprite have
; lower priority than the background so that it's partially obscured by the
; grass. Only the lower half of the sprite is permitted to have the priority
; bit set by later logic.
	ld a, [hTilePlayerStandingOn]
	ld c, a
	ld a, [wGrassTile]
	cp c
	ld a, $0
	jr nz, .next2
	ld a, $80
.next2
	ld [PlayerGrassPriority], a
	ret

UnusedReadSpriteDataFunction:
	push bc
	push af
	ld a, [H_CURRENTSPRITEOFFSET]
	ld c, a
	pop af
	add c
	ld l, a
	pop bc
	ret

UpdateNPCSprite:
	ld a, [H_CURRENTSPRITEOFFSET]
	swap a
	dec a
	add a
	ld hl, wMapSpriteData
	add l
	ld l, a
	ld a, [hl]        ; read movement byte 2
	ld [wCurSpriteMovement2], a
	ld h, wSpriteStateData1 / $100
	ld a, [H_CURRENTSPRITEOFFSET]
	ld l, a
	inc l
	ld a, [hl]        ; $c1x1 (MovementStatus)
	and a
	jp z, InitializeSpriteStatus
	call CheckSpriteAvailability
	ret c             ; if sprite is invisible, on tile >=$60, in grass or player is currently walking
	ld h, wSpriteStateData1 / $100
	ld a, [H_CURRENTSPRITEOFFSET]
	ld l, a
	inc l
	ld a, [hl]        ; $c1x1 (MovementStatus)
	bit 7, a ; is the face player flag set?
	jp nz, MakeNPCFacePlayer
	ld b, a
	ld a, [wFontLoaded]
	bit 0, a
	jp nz, notYetMoving
	ld a, b
	cp $2
	jp z, UpdateSpriteMovementDelay  ; MovementStatus == 2
	cp $3
	jp z, UpdateSpriteInWalkingAnimation  ; MovementStatus == 3
	ld a, [wWalkCounter]
	and a
	ret nz           ; don't do anything yet if player is currently moving (redundant, already tested in CheckSpriteAvailability)
	call InitializeSpriteScreenPosition
	ld h, wSpriteStateData2 / $100
	ld a, [H_CURRENTSPRITEOFFSET]
	add $6
	ld l, a
	ld a, [hl]       ; $c2x6 (MovementByte1)
	inc a
	jr z, .randomMovement  ; value $FF
	inc a
	jr z, .randomMovement  ; value $FE
; scripted movement
	dec a
	ld [hl], a       ; increment MovementByte1 (movement data index)
	dec a
	push hl
	ld hl, wNPCNumScriptedSteps
	dec [hl]         ; decrement wNPCNumScriptedSteps
	pop hl
	ld de, wNPCMovementDirections
	call LoadDEPlusA ; a = [wNPCMovementDirections + MovementByte1]
	cp $e0
	jp z, ChangeFacingDirection
	cp STAY
	jr nz, .next
; reached end of wNPCMovementDirections list
	ld [hl], a ; store $ff in MovementByte1, disabling scripted movement
	ld hl, wd730
	res 0, [hl]
	xor a
	ld [wSimulatedJoypadStatesIndex], a
	ld [wWastedByteCD3A], a
	ret
.next
	cp WALK
	jr nz, .determineDirection
; current NPC movement data is $fe. this seems buggy
	ld [hl], $1     ; set movement byte 1 to $1
	ld de, wNPCMovementDirections
	call LoadDEPlusA ; a = [wNPCMovementDirections + $fe] (?)
	jr .determineDirection
.randomMovement
	call GetTileSpriteStandsOn
	call Random
.determineDirection
	ld b, a
	ld a, [wCurSpriteMovement2]
	cp $d0
	jr z, .moveDown    ; movement byte 2 = $d0 forces down
	cp $d1
	jr z, .moveUp      ; movement byte 2 = $d1 forces up
	cp $d2
	jr z, .moveLeft    ; movement byte 2 = $d2 forces left
	cp $d3
	jr z, .moveRight   ; movement byte 2 = $d3 forces right
	ld a, b
	cp $40             ; a < $40: down (or left)
	jr nc, .notDown
	ld a, [wCurSpriteMovement2]
	cp $2
	jr z, .moveLeft    ; movement byte 2 = $2 only allows left or right
.moveDown
	ld de, 2*SCREEN_WIDTH
	add hl, de         ; move tile pointer two rows down
	lb de, 1, 0
	lb bc, 4, SPRITE_FACING_DOWN
	jr TryWalking
.notDown
	cp $80             ; $40 <= a < $80: up (or right)
	jr nc, .notUp
	ld a, [wCurSpriteMovement2]
	cp $2
	jr z, .moveRight   ; movement byte 2 = $2 only allows left or right
.moveUp
	ld de, -2*SCREEN_WIDTH
	add hl, de         ; move tile pointer two rows up
	lb de, -1, 0
	lb bc, 8, SPRITE_FACING_UP
	jr TryWalking
.notUp
	cp $c0             ; $80 <= a < $c0: left (or up)
	jr nc, .notLeft
	ld a, [wCurSpriteMovement2]
	cp $1
	jr z, .moveUp      ; movement byte 2 = $1 only allows up or down
.moveLeft
	dec hl
	dec hl             ; move tile pointer two columns left
	lb de, 0, -1
	lb bc, 2, SPRITE_FACING_LEFT
	jr TryWalking
.notLeft              ; $c0 <= a: right (or down)
	ld a, [wCurSpriteMovement2]
	cp $1
	jr z, .moveDown    ; movement byte 2 = $1 only allows up or down
.moveRight
	inc hl
	inc hl             ; move tile pointer two columns right
	lb de, 0, 1
	lb bc, 1, SPRITE_FACING_RIGHT
	jr TryWalking

; changes facing direction by zeroing the movement delta and calling TryWalking
ChangeFacingDirection:
	ld de, $0
	; fall through

; b: direction (1,2,4 or 8)
; c: new facing direction (0,4,8 or $c)
; d: Y movement delta (-1, 0 or 1)
; e: X movement delta (-1, 0 or 1)
; hl: pointer to tile the sprite would walk onto
; set carry on failure, clears carry on success
TryWalking:
	push hl
	ld h, wSpriteStateData1 / $100
	ld a, [H_CURRENTSPRITEOFFSET]
	add $9
	ld l, a
	ld [hl], c          ; $c1x9 (FacingDirection)
	ld a, [H_CURRENTSPRITEOFFSET]
	add $3
	ld l, a
	ld [hl], d          ; $c1x3 (YStepVector)
	inc l
	inc l
	ld [hl], e          ; $c1x5 (XStepVector)
	pop hl
	push de
	ld c, [hl]          ; read tile to walk onto
	call CanWalkOntoTile
	pop de
	ret c               ; cannot walk there (reinitialization of delay values already done)
	ld h, wSpriteStateData2 / $100
	ld a, [H_CURRENTSPRITEOFFSET]
	add $4
	ld l, a
	ld a, [hl]          ; $c2x4 (YPosition)
	add d
	ld [hli], a         ; update YPosition
	ld a, [hl]          ; $c2x5: (XPosition)
	add e
	ld [hl], a          ; update XPosition
	ld a, [H_CURRENTSPRITEOFFSET]
	ld l, a
	ld [hl], $10        ; $c2x0 (WalkAnimationCounter) = 16
	dec h
	inc l
	ld [hl], $3         ; set $c1x1 (MovementStatus) to walking
	jp UpdateSpriteImage

; update the walking animation parameters for a sprite that is currently walking
UpdateSpriteInWalkingAnimation:
	ld a, [H_CURRENTSPRITEOFFSET]
	add $7
	ld l, a
	ld a, [hl]                       ; $c1x7 (IntraAnimFrameCounter)
	inc a
	ld [hl], a                       ; IntraAnimFrameCounter += 1
	cp $4
	jr nz, .noNextAnimationFrame
	xor a
	ld [hl], a                       ; IntraAnimFrameCounter = 0
	inc l
	ld a, [hl]                       ; $c1x8 (AnimFrameCounter)
	inc a
	and $3
	ld [hl], a                       ; advance to next animation frame every 4 ticks (16 ticks total for one step)
.noNextAnimationFrame
	ld a, [H_CURRENTSPRITEOFFSET]
	add $3
	ld l, a
	ld a, [hli]                      ; $c1x3 (YStepVector)
	ld b, a
	ld a, [hl]                       ; $c1x4 (YPixels)
	add b
	ld [hli], a                      ; update YPixels
	ld a, [hli]                      ; $c1x5 (XStepVector)
	ld b, a
	ld a, [hl]                       ; $c1x6 (XPixels)
	add b
	ld [hl], a                       ; update XPixels
	ld a, [H_CURRENTSPRITEOFFSET]
	ld l, a
	inc h
	ld a, [hl]                       ; $c2x0 (WalkAnimationCounter)
	dec a
	ld [hl], a                       ; update WalkAnimationCounter
	ret nz
	ld a, $6                         ; walking finished, update state
	add l
	ld l, a
	ld a, [hl]                       ; $c2x6 (MovementByte1)
	cp $fe
	jr nc, .initNextMovementCounter  ; values $fe and $ff
	ld a, [H_CURRENTSPRITEOFFSET]
	inc a
	ld l, a
	dec h
	ld [hl], $1                      ; $c1x1 (MovementStatus) = 1 (ready)
	ret
.initNextMovementCounter
	call Random
	ld a, [H_CURRENTSPRITEOFFSET]
	add $8
	ld l, a
	ld a, [hRandomAdd]
	and $7f
	ld [hl], a                       ; set $c2x8 (MovementDelay) to a random value in [0,$7f]
	dec h                            ;       note that value 0 actually makes the delay $100 (bug?)
	ld a, [H_CURRENTSPRITEOFFSET]
	inc a
	ld l, a
	ld [hl], $2                      ; $c1x1 (MovementStatus) = 2
	inc l
	inc l
	xor a
	ld b, [hl]                       ; $c1x3 (YStepVector)
	ld [hli], a                      ; reset YStepVector
	inc l
	ld c, [hl]                       ; $c1x5 (XStepVector)
	ld [hl], a                       ; reset XStepVector
	ret

; update MovementDelay for sprites with a delayed MovementStatus
UpdateSpriteMovementDelay:
	ld h, wSpriteStateData2 / $100
	ld a, [H_CURRENTSPRITEOFFSET]
	add $6
	ld l, a
	ld a, [hl]              ; $c2x6 (MovementByte1)
	inc l
	inc l
	cp $fe
	jr nc, .tickMoveCounter ; values $fe or $ff
	ld [hl], $0
	jr .moving
.tickMoveCounter
	dec [hl]                ; $c2x8 (MovementDelay)
	jr nz, notYetMoving
.moving
	dec h
	ld a, [H_CURRENTSPRITEOFFSET]
	inc a
	ld l, a
	ld [hl], $1             ; $c1x1 (MovementStatus) = 1
notYetMoving:
	ld h, wSpriteStateData1 / $100
	ld a, [H_CURRENTSPRITEOFFSET]
	add $8
	ld l, a
	ld [hl], $0             ; $c1x8 = 0 (walk animation frame)
	jp UpdateSpriteImage

MakeNPCFacePlayer:
; Make an NPC face the player if the player has spoken to him or her.

; Check if the behaviour of the NPC facing the player when spoken to is
; disabled. This is only done when rubbing the S.S. Anne captain's back.
	ld a, [wd72d]
	bit 5, a
	jr nz, notYetMoving
	res 7, [hl]
	ld a, [wPlayerDirection]
	bit PLAYER_DIR_BIT_UP, a
	jr z, .notFacingDown
	ld c, SPRITE_FACING_DOWN
	jr .facingDirectionDetermined
.notFacingDown
	bit PLAYER_DIR_BIT_DOWN, a
	jr z, .notFacingUp
	ld c, SPRITE_FACING_UP
	jr .facingDirectionDetermined
.notFacingUp
	bit PLAYER_DIR_BIT_LEFT, a
	jr z, .notFacingRight
	ld c, SPRITE_FACING_RIGHT
	jr .facingDirectionDetermined
.notFacingRight
	ld c, SPRITE_FACING_LEFT
.facingDirectionDetermined
	ld a, [H_CURRENTSPRITEOFFSET]
	add $9
	ld l, a
	ld [hl], c              ; $c1x9 (FacingDirection)
	jr notYetMoving

InitializeSpriteStatus:
	ld [hl], $1   ; $c1x1 (MovementStatus) = ready
	inc l
	ld [hl], $ff  ; $c1x2 (SpriteImageIdx) = $ff (invisible/off screen)
	inc h
	ld a, [H_CURRENTSPRITEOFFSET]
	add $2
	ld l, a
	ld a, $8
	ld [hli], a   ; $c2x2 (YDisplacement) set Y displacement to 8
	ld [hl], a    ; $c2x3 (XDisplacement) set X displacement to 8
	ret

; calculates the sprites's screen position from its map position and the player position
InitializeSpriteScreenPosition:
	call GetSpriteScreenPosition
	ld h, wSpriteStateData1 / $100
	ld a, [H_CURRENTSPRITEOFFSET]
	add $4
	ld l, a
	ld a, c
	ld [hli], a     ; $c1x4 (YPixels)
	inc l
	ld a, b
	ld [hl], a      ; $c1x6 (XPixels)
	ret

; calculates the sprite's screen position from its map position and the player position
; if the sprite is partially or fully on-screen, returns xy in bc
; if the sprite is entirely off-screen, returns $f0ec (i.e. -SPRITE_WIDTH, -SPRITE_HEIGHT) in bc
GetSpriteScreenPosition:
	ld h, wSpriteStateData2 / $100
	ld a, [H_CURRENTSPRITEOFFSET]
	add $4
	ld l, a
	ld a, [wYCoord]
	ld b, a
	ld a, [hli]     ; $c2x4 (YPosition)
	sub b           ; relative to map scroll
	jr c, .offScreen; above top of screen
	cp 16           ; check for overflow (below bottom of screen)
	jr nc, .offScreen
	swap a          ; * 16
	sub $4          ; - 4
	ld c, a
	ld a, [wXCoord]
	ld b, a
	ld a, [hl]      ; $c2x5 (XPosition)
	sub b           ; relative to map scroll
	jr c, .offScreen; left of left of screen
	cp 16           ; check for overflow (right of right of screen)
	jr nc, .offScreen
	swap a          ; * 16
	ld b, a
	ret
.offScreen
	ld bc, $100*($100-SPRITE_WIDTH_PIXELS) + ($100-SPRITE_HEIGHT_PIXELS)
	ret

; tests if sprite is off screen or otherwise unable to do anything
CheckSpriteAvailability:
	predef IsObjectHidden
	ld a, [$ffe5]
	and a
	jp nz, .spriteInvisible
	ld h, wSpriteStateData2 / $100
	ld a, [H_CURRENTSPRITEOFFSET]
	add $6
	ld l, a
	ld a, [hl]      ; $c2x6 (MovementByte1)
	cp $fe
	jr c, .skipVisibilityTest ; MovementByte1 < $fe (i.e. the sprite's movement is scripted)

; make the sprite invisible if it's off-screen
	call GetSpriteScreenPosition
; if (XPixels + SPRITE_WIDTH_PIXELS <= 0 || XPixels >= SCREEN_WIDTH_PIXELS) jr .spriteInvisible
	ld a, b
	add SPRITE_WIDTH_PIXELS
	cp 0 ; TODO Invert
	jr c, .spriteInvisible
	jr z, .spriteInvisible
	ld a, b
	add SPRITE_WIDTH_PIXELS
	cp SCREEN_WIDTH_PIXELS + SPRITE_WIDTH_PIXELS
	jr nc, .spriteInvisible

; if (YPixels + SPRITE_HEIGHT_PIXELS <= 0 || YPixels >= SCREEN_HEIGHT_PIXELS) jr .spriteInvisible
	ld a, c
	add SPRITE_HEIGHT_PIXELS
	cp 0
	jr c, .spriteInvisible
	jr z, .spriteInvisible
	ld a, c
	add SPRITE_HEIGHT_PIXELS
	cp SCREEN_HEIGHT_PIXELS + SPRITE_HEIGHT_PIXELS
	jr nc, .spriteInvisible

.skipVisibilityTest:
; make the sprite invisible if a text box is in front of it
; $5F is the maximum number for map tiles
	call GetTileSpriteStandsOn
	ld d, $60
	ld a, [hli]
	cp d
	jr nc, .spriteInvisible ; standing on tile with ID >=$60 (bottom left tile)
	ld a, [hld]
	cp d
	jr nc, .spriteInvisible ; standing on tile with ID >=$60 (bottom right tile)
	ld bc, -20
	add hl, bc              ; go back one row of tiles
	ld a, [hli]
	cp d
	jr nc, .spriteInvisible ; standing on tile with ID >=$60 (top left tile)
	ld a, [hl]
	cp d
	jr c, .spriteVisible    ; standing on tile with ID >=$60 (top right tile)
.spriteInvisible
	ld h, wSpriteStateData1 / $100
	ld a, [H_CURRENTSPRITEOFFSET]
	add $2
	ld l, a
	ld [hl], $ff       ; $c1x2
	scf
	jr .done
.spriteVisible
	ld c, a
	ld a, [wWalkCounter] ;;;
	and a ;;;
	jr nz, .done           ; if player is currently walking, we're done ;;;
	call UpdateSpriteImage
	inc h
	ld a, [H_CURRENTSPRITEOFFSET]
	add $7
	ld l, a
	ld a, [wGrassTile]
	cp c
	ld a, $0
	jr nz, .notInGrass
	ld a, $80
.notInGrass
	ld [hl], a       ; $c2x7
	and a
.done
	ret

UpdateSpriteImage:
	ld h, wSpriteStateData1 / $100
	ld a, [H_CURRENTSPRITEOFFSET]
	add $8
	ld l, a
	ld a, [hli]        ; $c1x8 (AnimFrameCounter)
	ld b, a
	ld a, [hl]         ; $c1x9 (FacingDirection)
	add b
	ld b, a
	ld a, [$ff93]  ; current sprite offset
	add b
	ld b, a
	ld a, [H_CURRENTSPRITEOFFSET]
	add $2
	ld l, a
	ld [hl], b         ; $c1x2 (SpriteImageIdx)
	ret

; tests if sprite can walk the specified direction
; b: direction (1,2,4 or 8)
; c: ID of tile the sprite would walk onto
; d: Y movement delta (-1, 0 or 1)
; e: X movement delta (-1, 0 or 1)
; set carry on failure, clears carry on success
CanWalkOntoTile:
	ld h, wSpriteStateData2 / $100
	ld a, [H_CURRENTSPRITEOFFSET]
	add $6
	ld l, a
	ld a, [hl]         ; $c2x6 (MovementByte1)
	cp $fe
	jr nc, .notScripted    ; values $fe and $ff
; always allow walking if the movement is scripted
	and a
	ret
.notScripted
	ld a, [wTilesetCollisionPtr]
	ld l, a
	ld a, [wTilesetCollisionPtr+1]
	ld h, a
.tilePassableLoop
	ld a, [hli]
	cp $ff
	jr z, .impassable
	cp c
	jr nz, .tilePassableLoop
	ld h, wSpriteStateData2 / $100
	ld a, [H_CURRENTSPRITEOFFSET]
	add $6
	ld l, a
	ld a, [hl]         ; $c2x6 (MovementByte1)
	inc a
	jr z, .impassable  ; if $ff, no movement allowed (however, changing direction is)
	ld h, wSpriteStateData1 / $100
	ld a, [H_CURRENTSPRITEOFFSET]
	add $4
	ld l, a
	ld a, [hli]        ; $c1x4 (YPixels)
	add $4             ; align to blocks (Y pos is always 4 pixels off)
	add d              ; add Y delta
	cp $80             ; if value is >$80, the destination is off screen (either $81 or $FF underflow)
	jr nc, .impassable ; don't walk off screen
	inc l
	ld a, [hl]         ; $c1x6 (XPixels)
	add e              ; add X delta
	cp $90             ; if value is >$90, the destination is off screen (either $91 or $FF underflow)
	jr nc, .impassable ; don't walk off screen
	push de
	push bc
	call DetectCollisionBetweenSprites
	pop bc
	pop de
	ld h, wSpriteStateData1 / $100
	ld a, [H_CURRENTSPRITEOFFSET]
	add $c
	ld l, a
	ld a, [hl]         ; $c1xc (CollisionDirections)
	and b              ; check against chosen direction (1,2,4 or 8)
	jr nz, .impassable ; collision between sprites, don't go there
	ld h, wSpriteStateData2 / $100
	ld a, [H_CURRENTSPRITEOFFSET]
	add $2
	ld l, a
	ld a, [hli]        ; $c2x2 (YDisplacement, initialized at $8, keep track of where a sprite did go)
	bit 7, d           ; check if going upwards (d=$ff)
	jr nz, .upwards
	add d
	cp $5
	jr c, .impassable  ; if YDisplacement+d < 5, don't go ;bug: this tests probably were supposed to prevent sprites
	jr .checkHorizontal                                   ; from walking out too far, but this line makes sprites get stuck
.upwards                                                  ; whenever they walked upwards 5 steps
	sub $1                                                ; on the other hand, the amount a sprite can walk out to the
	jr c, .impassable  ; if YDisplacement == 0, don't go  ; right of bottom is not limited (until the counter overflows)
.checkHorizontal
	ld d, a
	ld a, [hl]         ; $c2x3 (XDisplacement, initialized at $8, keep track of where a sprite did go)
	bit 7, e           ; check if going left (e=$ff)
	jr nz, .left
	add e
	cp $5              ; compare, but no conditional jump like in the vertical check above (bug?)
	jr .passable
.left
	sub $1
	jr c, .impassable  ; if XDisplacement == 0, don't go
.passable
	ld [hld], a        ; update XDisplacement
	ld [hl], d         ; update YDisplacement
	and a              ; clear carry (marking success)
	ret
.impassable
	ld h, wSpriteStateData1 / $100
	ld a, [H_CURRENTSPRITEOFFSET]
	inc a
	ld l, a
	ld [hl], $2        ; $c1x1 (MovementStatus) = 2 (delayed)
	inc l
	inc l
	xor a
	ld [hli], a        ; $c1x3 (YStepVector) = 0
	inc l
	ld [hl], a         ; $c1x5 (XStepVector) = 0
	inc h
	ld a, [H_CURRENTSPRITEOFFSET]
	add $8
	ld l, a
	call Random
	ld a, [hRandomAdd]
	and $7f
	ld [hl], a         ; set $c2x8 (MovementDelay) to a random value in [0,$7f] (again with delay $100 if value is 0)
	scf                ; set carry (marking failure to walk)
	ret

; calculates the tile pointer pointing to the tile the current sprite stands on
; this is always the lower left tile of the 2x2 tile blocks all sprites are snapped to
; hl: output pointer
GetTileSpriteStandsOn:
	ld h, wSpriteStateData1 / $100
	ld a, [H_CURRENTSPRITEOFFSET]
	add $4
	ld l, a
	ld a, [hli]     ; $c1x4 (YPixels)
	add $4          ; align to 2*2 tile blocks (Y position is always off 4 pixels to the top)
	and $f0         ; in case object is currently moving
	srl a           ; screen Y tile * 4
	ld c, a
	ld b, $0
	inc l
	ld a, [hl]      ; $c1x6 (XPixels)
	srl a
	srl a
	srl a            ; screen X tile
	add SCREEN_WIDTH ; screen X tile + 20
	ld d, $0
	ld e, a
	coord hl, 0, 0
	add hl, bc
	add hl, bc
	add hl, bc
	add hl, bc
	add hl, bc
	add hl, de     ; wTileMap + 20*(screen Y tile + 1) + screen X tile
	ret

; loads [de+a] into a
LoadDEPlusA:
	add e
	ld e, a
	jr nc, .noCarry
	inc d
.noCarry
	ld a, [de]
	ret

DoScriptedNPCMovement:
; This is an alternative method of scripting an NPC's movement and is only used
; a few times in the game. It is used when the NPC and player must walk together
; in sync, such as when the player is following the NPC somewhere. An NPC can't
; be moved in sync with the player using the other method.
	ld a, [wd730]
	bit 7, a
	ret z
	ld hl, wd72e
	bit 7, [hl]
	set 7, [hl]
	jp z, InitScriptedNPCMovement
	ld hl, wNPCMovementDirections2
	ld a, [wNPCMovementDirections2Index]
	add l
	ld l, a
	jr nc, .noCarry
	inc h
.noCarry
	ld a, [hl]
; check if moving up
	cp NPC_MOVEMENT_UP
	jr nz, .checkIfMovingDown
	call GetSpriteScreenYPointer
	ld c, SPRITE_FACING_UP
	ld a, -2
	jr .move
.checkIfMovingDown
	cp NPC_MOVEMENT_DOWN
	jr nz, .checkIfMovingLeft
	call GetSpriteScreenYPointer
	ld c, SPRITE_FACING_DOWN
	ld a, 2
	jr .move
.checkIfMovingLeft
	cp NPC_MOVEMENT_LEFT
	jr nz, .checkIfMovingRight
	call GetSpriteScreenXPointer
	ld c, SPRITE_FACING_LEFT
	ld a, -2
	jr .move
.checkIfMovingRight
	cp NPC_MOVEMENT_RIGHT
	jr nz, .noMatch
	call GetSpriteScreenXPointer
	ld c, SPRITE_FACING_RIGHT
	ld a, 2
	jr .move
.noMatch
	cp $ff
	ret
.move
	ld b, a
	ld a, [hl]
	add b
	ld [hl], a
	ld a, [H_CURRENTSPRITEOFFSET]
	add $9
	ld l, a
	ld a, c
	ld [hl], a ; $c1x9 (FacingDirection)
	call AnimScriptedNPCMovement
	ld hl, wScriptedNPCWalkCounter
	dec [hl]
	ret nz
	ld a, 8
	ld [wScriptedNPCWalkCounter], a
	ld hl, wNPCMovementDirections2Index
	inc [hl]
	ret

InitScriptedNPCMovement:
	xor a
	ld [wNPCMovementDirections2Index], a
	ld a, 8
	ld [wScriptedNPCWalkCounter], a
	jp AnimScriptedNPCMovement

; sets hl to $c1x4 (YPixels) for the current sprite
GetSpriteScreenYPointer:
	ld a, $4
	ld b, a
	jr GetSpriteScreenXYPointerCommon

; sets hl to $c1x4 (XPixels) for the current sprite
GetSpriteScreenXPointer:
	ld a, $6
	ld b, a

GetSpriteScreenXYPointerCommon:
	ld hl, wSpriteStateData1
	ld a, [H_CURRENTSPRITEOFFSET]
	add l
	add b
	ld l, a
	ret

AnimScriptedNPCMovement:
	ld hl, wSpriteStateData2
	ld a, [H_CURRENTSPRITEOFFSET]
	add $e
	ld l, a
	ld a, [hl] ; $c2xe (SpriteImageBaseOffset)
	dec a
	swap a
	ld b, a
	ld hl, wSpriteStateData1
	ld a, [H_CURRENTSPRITEOFFSET]
	add $9
	ld l, a
	ld a, [hl] ; $c1x9 (FacingDirection)
	cp SPRITE_FACING_DOWN
	jr z, .anim
	cp SPRITE_FACING_UP
	jr z, .anim
	cp SPRITE_FACING_LEFT
	jr z, .anim
	cp SPRITE_FACING_RIGHT
	jr z, .anim
	ret
.anim
	add b
	ld b, a
	ld [hSpriteVRAMSlotAndFacing], a
	call AdvanceScriptedNPCAnimFrameCounter
	ld hl, wSpriteStateData1
	ld a, [H_CURRENTSPRITEOFFSET]
	add $2
	ld l, a
	ld a, [hSpriteVRAMSlotAndFacing]
	ld b, a
	ld a, [hSpriteAnimFrameCounter]
	add b
	ld [hl], a ; $c1x2 (SpriteImageIdx)
	ret

; assumes h = wSpriteStateData1 / $100
AdvanceScriptedNPCAnimFrameCounter:
	ld a, [H_CURRENTSPRITEOFFSET]
	add $7
	ld l, a
	ld a, [hl] ; $c1x7 (IntraAnimFrameCounter)
	inc a
	ld [hl], a
	cp 4
	ret nz
	xor a
	ld [hl], a ; reset IntraAnimFrameCounter
	inc l
	ld a, [hl] ; $c1x8 (AnimFrameCounter)
	inc a
	and $3
	ld [hl], a
	ld [hSpriteAnimFrameCounter], a
	ret
