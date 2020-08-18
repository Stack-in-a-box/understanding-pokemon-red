; **InitMapSprites**  
; マップ上のスプライトのタイルパターンをロードする関数  
; - - -  
; 外部マップの場合は、いくつかの固定されたスプライトのセットの1つをロードします。
; 建物などの内部マップでは、この関数は Map Headerで使われている各スプライトの picture IDをロードする  
; 会話時にはテキストのタイルパターンがスプライトのタイルパターンデータを半分上書きしてしまうので、会話終了時にもこの関数が呼ばれる  
; 
; Note on notation:
; $C1X* and $C2X* are used to denote wSpriteStateData1-wSpriteStateData1 + $ff and wSpriteStateData2 + $00-wSpriteStateData2 + $ff sprite slot
; fields, respectively, within loops. The X is the loop index.
; If there is an inner loop, Y is the inner loop index, i.e. $C1Y* and $C2Y*
; denote fields of the sprite slots iterated over in the inner loop.
InitMapSprites:
	call InitOutsideMapSprites
	ret c ; return if the map is an outside map (already handled by above call)
; if the map is an inside map (i.e. mapID >= $25)
	ld hl, wSpriteStateData1
	ld de, wSpriteStateData2 + $0d
; Loop to copy picture ID's from $C1X0 to $C2XD for LoadMapSpriteTilePatterns.
.copyPictureIDLoop
	ld a, [hl] ; $C1X0 (picture ID)
	ld [de], a ; $C2XD
	ld a, $10
	add e
	ld e, a
	ld a, $10
	add l
	ld l, a
	jr nz, .copyPictureIDLoop

; **LoadMapSpriteTilePatterns**  
; スプライトのタイルデータを VRAM にロードする関数  
; - - -  
; この関数は InitOutsideMapSprites によって呼ばれるため、 内部マップでも外部マップでも利用される  
LoadMapSpriteTilePatterns:
	; 処理対象のスプライトがもうない -> return
	ld a, [wNumSprites]
	and a ; are there any sprites?
	jr nz, .spritesExist
	ret

.spritesExist
	ld c, a ; c = [wNumSprites]
	ld b, $10 ; スプライトスロットの数 (wSpriteStateData1 は 全部で16スプライト分なので 0x10)
	ld hl, wSpriteStateData2 + $0d
	xor a
	ld [hFourTileSpriteCount], a	; 各スプライトは 8*8タイル4枚からなるのでそのカウンタ

; 各$C2XD に格納されている sprite picture ID を $C2XE にコピーしていく
.copyPictureIDLoop 
; {
	ld a, [hli] ; $C2XD (sprite picture ID)
	ld [hld], a ; $C2XE
	ld a, l
	add $10
	ld l, a
	dec b
	jr nz, .copyPictureIDLoop
; }

	ld hl, wSpriteStateData2 + $1e
.loadTilePatternLoop
	ld de, wSpriteStateData2 + $1d
; 現在の picutire ID に対応するタイルデータがすでにロード済か確認する  
; wSpriteStateData2 の16個のスプライトについてループを通して1つずつ確認していく  
; すでに確認済のスプライトを見ていき picture IDが現在処理中のスプライトの picture ID と一致した場合ロード済とする  
; 未ロードの場合はロード処理を行う
.checkIfAlreadyLoadedLoop
; {
	; b = 比較対象のスプライト(すでに確認済のスプライト)のオフセット
	ld a, e
	and $f0
	ld b, a

	; a = 確認対象のスプライト
	ld a, l
	and $f0

	; 確認対象のスプライトより前のスプライトをすべてチェックした -> .notAlreadyLoaded
	cp b
	jr z, .notAlreadyLoaded

	; 前のスプライトに picture IDが一致するものが見つかった -> .alreadyLoaded
	ld a, [de]	; c2XD
	cp [hl]		; c2YE
	jp z, .alreadyLoaded

	; 次のスロットへ
	ld a, e
	add $10
	ld e, a
	jr .checkIfAlreadyLoadedLoop
; }

.notAlreadyLoaded
	ld de, wSpriteStateData2 + $0e
	ld b, $01
	; この時点で hl は現在処理中のスプライトの c2XE

; VRAMスロットのうち空いている場所をVRAMスロットが10以内の範囲で前から探していく
.findNextVRAMSlotLoop
	ld a, e
	add $10
	ld e, a

	; 以前のスプライトを全て見た -> .foundNextVRAMSlot
	ld a, l
	cp e
	jr z, .foundNextVRAMSlot

	; 見ているスプライトスロットのスプライトのタイルデータのVRAM内オフセットが 10スロット以降にある -> .findNextVRAMSlotLoop
	ld a, [de] ; $C2YE (VRAM slot)
	cp 11 ; is it one of the first 10 slots?
	jr nc, .findNextVRAMSlotLoop

	; 10スロット以内の場合
	cp b ; compare the slot being checked to the current max
	jr c, .findNextVRAMSlotLoop ; if the slot being checked is less than the current max

; if the slot being checked is greater than or equal to the current max
	ld b, a ; store new max VRAM slot
	jr .findNextVRAMSlotLoop

; この時点で b = スプライトのタイルデータのために使われているVRAMスロットの最大値 (つまりこれ以降はVRAMスロットが空いている 1から数える)

.foundNextVRAMSlot
	inc b ; b = 空きVRAMスロットのオフセット

	ld a, b ; a = 空きVRAMスロットのオフセット
	push af

	ld a, [hl] ; $C2XE (sprite picture ID)
	ld b, a ; b = current sprite picture ID

	; spriteID >= SPRITE_BALL の場合(3面スプライト)  a = 空きVRAMスロットのオフセット
	; spriteID < SPRITE_BALL  の場合(1面スプライト)  a = 11 + [hFourTileSpriteCount]
	cp SPRITE_BALL ; is it a 4-tile sprite?
	jr c, .notFourTileSprite 
	pop af
	ld a, [hFourTileSpriteCount]
	add 11
	jr .storeVRAMSlot
.notFourTileSprite
	pop af

	; この時点で a には処理中のスプライトのタイルデータを格納するVRAMオフセットが入っている

.storeVRAMSlot
	ld [hl], a ; c2XE = VRAMオフセット
	ld [hVRAMSlot], a ; used to determine if it's 4-tile sprite later
	
	; a = 3(spriteID-1)
	ld a, b ; a = spriteID
	dec a
	add a
	add a

	push bc
	push hl

	; hl = SpriteSheetPointerTableの該当エントリ
	ld hl, SpriteSheetPointerTable
	jr nc, .noCarry
	inc h
.noCarry
	add l
	ld l, a
	jr nc, .noCarry2
	inc h
.noCarry2

	push hl
	call ReadSpriteSheetData
	push af
	push de
	push bc

	ld hl, vNPCSprites 	; VRAM base address
	ld bc, $c0 			; 3面(上下右)スプライトの2bppデータのサイズ 2bppフォーマットの 1タイルが 0x10なので 0x0c * 0x10 

	; 対象のスプライトの spriteIDが SPRITE_BALL以上のとき、つまり 1面(4タイル)しかタイルデータを持たない場合 -> .fourTileSpriteVRAMAddr
	ld a, [hVRAMSlot]
	cp 11
	jr nc, .fourTileSpriteVRAMAddr

; 3面(上下右)スプライトのとき
; hl = vNPCSprites + ([hVRAMSlot]-1)*0xc0
	ld d, a	
	dec d	; VRAMスロットは1から数えているので
.calculateVRAMAddrLoop
; {
	add hl, bc
	dec d
	jr nz, .calculateVRAMAddrLoop
; }

	jr .loadStillTilePattern

.fourTileSpriteVRAMAddr
	; 前提として、VRAMに存在できる1面スプライトのタイルデータは2個まで
	; 0x8000-0x8800の末尾(0x8780-0x8800)を 1面スプライトが使う
	ld hl, vSprites + $7c0

	; [hFourTileSpriteCount] > 0 -> .loadStillTilePattern
	ld a, [hFourTileSpriteCount]
	and a
	jr nz, .loadStillTilePattern
	
	; [hFourTileSpriteCount] == 0 つまり 4タイルのうち最初の1タイルのとき
	ld hl, vSprites + $780
	inc a
	ld [hFourTileSpriteCount], a

	; つまり hl = vSprites + $780(最初の1面スプライト) or vSprites + $7c0(2個目の1面スプライト)

; この時点で hl = スプライトが格納される VRAMスロット(0x8000-0x8800のどこか)のアドレス
.loadStillTilePattern
	pop bc	; bc = 2bppデータのバイト長(bc = 0x0c or 0x04)
	pop de	; de = スプライトの2bppデータのアドレス
	pop af	; a = ROMバンク番号

	push hl
	push hl

	; hl = スプライトの2bppデータのアドレス
	ld h, d
	ld l, e

	pop de	; de = スプライトが格納される VRAMスロット(0x8000-0x8800のどこか)のアドレス
	
	ld b, a

	; テキスト表示後にこの関数が呼ばれた場合は、VRAMの上半分(0x8000-0x8800)にはスプライトデータが残っており、歩きモーションなどを格納する下半分(0x8800-0x8fff)だけがテキストデータで上書きされている
	; よってリロードの必要があるのは下半分だけなので上半分はスキップする
	ld a, [wFontLoaded]
	bit 0, a
	jr nz, .skipFirstLoad

; スプライトの上半分(立ち姿)の 2bppタイルデータを VRAMにロード
	ld a, b	; a = スプライトの2bppデータのROMバンク番号
	ld b, 0	; bc = スプライトの2bppデータのバイト長(bc = 0x0c or 0x04)
	; この時点で
	; hl = スプライトの2bppデータのアドレス
	; de = スプライトが格納される VRAMスロット(0x8000-0x8800のどこか)のアドレス
	call FarCopyData2

.skipFirstLoad
	pop de
	pop hl
	ld a, [hVRAMSlot]
	cp 11 ; is it a 4-tile sprite?
	jr nc, .skipSecondLoad ; if so, there is no second block
	push de
	call ReadSpriteSheetData
	push af
	ld a, $c0
	add e
	ld e, a
	jr nc, .noCarry3
	inc d
.noCarry3
	ld a, [wFontLoaded]
	bit 0, a ; reloading upper half of tile patterns after displaying text?
	jr nz, .loadWhileLCDOn
	pop af
	pop hl
	set 3, h ; add $800 to hl
	push hl
	ld h, d
	ld l, e
	pop de
	call FarCopyData2 ; load tile pattern data for sprite when walking
	jr .skipSecondLoad
; When reloading the upper half of tile patterns after displaying text, the LCD
; will be on, so CopyVideoData (which writes to VRAM only during V-blank) must
; be used instead of FarCopyData2.
.loadWhileLCDOn
	pop af
	pop hl
	set 3, h ; add $800 to hl
	ld b, a
	swap c
	call CopyVideoData ; load tile pattern data for sprite when walking
.skipSecondLoad
	pop hl
	pop bc
	jr .nextSpriteSlot
.alreadyLoaded ; if the current picture ID has already had its tile patterns loaded
	inc de
	ld a, [de] ; a = VRAM slot for the current picture ID (from $C2YE)
	ld [hl], a ; store VRAM slot in current wSpriteStateData2 sprite slot (at $C2XE)
.nextSpriteSlot
	ld a, l
	add $10
	ld l, a
	dec c
	jp nz, .loadTilePatternLoop
	ld hl, wSpriteStateData2 + $0d
	ld b, $10
; the pictures ID's stored at $C2XD are no longer needed, so zero them
.zeroStoredPictureIDLoop
	xor a
	ld [hl], a ; $C2XD
	ld a, $10
	add l
	ld l, a
	dec b
	jr nz, .zeroStoredPictureIDLoop
	ret

; **ReadSpriteSheetData**  
; SpriteSheetPointerTable からデータを読み取る  
; - - -  
; INPUT:  
; hl = SpriteSheetPointerTable の該当エントリ  
; 
; OUTPUT:  
; de = スプライトの2bppデータのアドレス  
; bc = 2bppデータのバイト長(bc = 0x0c or 0x04)  
; a = ROMバンク番号
ReadSpriteSheetData:
	; de = スプライトの2bppデータのアドレス
	ld a, [hli]
	ld e, a
	ld a, [hli]
	ld d, a
	; bc = 2bppデータのバイト長
	ld a, [hli]
	ld c, a
	xor a
	ld b, a
	; a = ROMバンク番号
	ld a, [hli]
	ret

; **InitOutsideMapSprites**  
; 外部マップ(町や道路)のスプライトセットをロードし、VRAMスロットにセットする  
; - - -  
; スプライトセットは `data/sprite_sets.asm` 参照  
; OUTPUT: carry = 1(対象が外部マップ) or 0(対象が内部マップ)
InitOutsideMapSprites:
	; [wCurMap] >= REDS_HOUSE_1F つまり マップが内部マップならキャリーをクリアして終了
	ld a, [wCurMap]
	cp REDS_HOUSE_1F ; 外部マップは全て < REDS_HOUSE_1F
	ret nc

	; a = spriteSetID (MapSpriteSets の該当エントリ)
	ld hl, MapSpriteSets
	add l
	ld l, a
	jr nc, .noCarry
	inc h
.noCarry
	ld a, [hl]

	; spriteSetID >= 0xf0 つまり マップが2つのスプライトセットを持っている -> GetSplitMapSpriteSetID
	cp $f0
	call nc, GetSplitMapSpriteSetID

	ld b, a ; b = spriteSetID

	; [wFontLoaded] の bit0 が立っている つまり テキストデータのタイルが VRAM の BGマップ の上半分にセットされている -> .loadSpriteSet
	ld a, [wFontLoaded]
	bit 0, a
	jr nz, .loadSpriteSet

	; 現在 VRAMにセットされている スプライトセット(wSpriteSetIDからわかる) が ロードしようとしているスプライトセットと等しい -> .skipLoadingSpriteSet
	ld a, [wSpriteSetID]
	cp b
	jr z, .skipLoadingSpriteSet

.loadSpriteSet
	; [wSpriteSetID] = ロードする spriteSetID
	ld a, b
	ld [wSpriteSetID], a

	; a = (spriteSetID - 1) * 11
	dec a
	ld b, a
	sla a
	ld c, a
	sla a
	sla a
	add c
	add b
	
	; de = SpriteSets の該当エントリ (11個ごとの区切りの先頭)
	ld de, SpriteSets
	add e
	ld e, a
	jr nc, .noCarry2
	inc d
.noCarry2
	; $C20D はプレイヤーのスプライトIDのスロットなので SPRITE_REDで固定
	ld hl, wSpriteStateData2 + $0d
	ld a, SPRITE_RED
	ld [hl], a

	ld bc, wSpriteSet

; スプライトセット(の中身の sprite picture ID)を wSpriteSet と 各 $C2XD にセットしていく
; これは、 LoadMapSpriteTilePatterns がスプライトセット内のすべてのスプライトのタイルパターンを読み込むように行われます。  
.loadSpriteSetLoop
; {
	; ループ開始時 
	; bc は wSpriteSetの新しいエントリ
	; de は処理対象のスプライトIDを指している (SpriteSets の該当スプライトセット(11個の塊)の中の該当スプライト)

	; hl += 0x10 (次の スプライトの C2XD)
	ld a, $10
	add l
	ld l, a

	; スプライトセットから取得した スプライトID を C2XD にセット
	ld a, [de]
	ld [hl], a

	; bc, de を次のエントリへ
	ld [bc], a
	inc de
	inc bc

	; スプライトセット全てを処理し終えたら終了 (11個目のスプライトを処理したら終了)
	ld a, l
	cp $bd
	jr nz, .loadSpriteSetLoop
; }

; 残り4つの wSpriteStateData2 の c2XDを 0クリアする
	ld b, 4
.zeroRemainingSlotsLoop
; {
	ld a, $10
	add l
	ld l, a
	xor a
	ld [hl], a ; $C2XD (sprite picture ID)
	dec b
	jr nz, .zeroRemainingSlotsLoop
; }

	; [wNumSprites] を退避
	ld a, [wNumSprites]
	push af ; save number of sprites

	ld a, 11 ; 11 sprites in sprite set
	ld [wNumSprites], a
	call LoadMapSpriteTilePatterns

	; [wNumSprites] を下に戻す
	pop af
	ld [wNumSprites], a ; restore number of sprites

	ld hl, wSpriteStateData2 + $1e
	ld b, $0f
; The VRAM tile pattern slots that LoadMapSpriteTilePatterns set are in the
; order of the map's sprite set, not the order of the actual sprites loaded
; for the current map. So, they are not needed and are zeroed by this loop.
.zeroVRAMSlotsLoop
	xor a
	ld [hl], a ; $C2XE (VRAM slot)
	ld a, $10
	add l
	ld l, a
	dec b
	jr nz, .zeroVRAMSlotsLoop
.skipLoadingSpriteSet
	ld hl, wSpriteStateData1 + $10
; This loop stores the correct VRAM tile pattern slots according the sprite
; data from the map's header. Since the VRAM tile pattern slots are filled in
; the order of the sprite set, in order to find the VRAM tile pattern slot
; for a sprite slot, the picture ID for the sprite is looked up within the
; sprite set. The index of the picture ID within the sprite set plus one
; (since the Red sprite always has the first VRAM tile pattern slot) is the
; VRAM tile pattern slot.
.storeVRAMSlotsLoop
	ld c, 0
	ld a, [hl] ; $C1X0 (picture ID) (zero if sprite slot is not used)
	and a ; is the sprite slot used?
	jr z, .skipGettingPictureIndex ; if the sprite slot is not used
	ld b, a ; b = picture ID
	ld de, wSpriteSet
; Loop to find the index of the sprite's picture ID within the sprite set.
.getPictureIndexLoop
	inc c
	ld a, [de]
	inc de
	cp b ; does the picture ID match?
	jr nz, .getPictureIndexLoop
	inc c
.skipGettingPictureIndex
	push hl
	inc h
	ld a, $0e
	add l
	ld l, a
	ld a, c ; a = VRAM slot (zero if sprite slot is not used)
	ld [hl], a ; $C2XE (VRAM slot)
	pop hl
	ld a, $10
	add l
	ld l, a
	and a
	jr nz, .storeVRAMSlotsLoop
	scf
	ret

; **GetSplitMapSpriteSetID**  
; 2つのスプライトセットを持つマップの場合、マップ内でのプレーヤーの位置に応じて、正しい spriteSetID を選択する関数  
; - - -  
; MapSpriteSets から取得した spriteSetID が 0xf0 以上の場合、そのまま spriteSetID として使うのではなく
; SplitMapSpriteSets を通して正しい spriteSetID に変換して使う  
; 
; INPUT: a = 0xf0以上の spriteSetID (MapSpriteSets のエントリ)  
; OUTPUT: a = spriteSetID  
GetSplitMapSpriteSetID:
	; spriteSetID == 0xf8 -> .route20
	cp $f8
	jr z, .route20

	; hl = SplitMapSpriteSets の該当エントリのアドレス
	ld hl, SplitMapSpriteSets
	and $0f
	dec a
	sla a
	sla a		; エントリは 4byteなので a << 2
	add l
	ld l, a
	jr nc, .noCarry
	inc h
.noCarry

	; a = [wXCoord](東西分割) or [wYCoord](南北分割)
	; b = 境界線の coord
	ld a, [hli]
	cp $01
	ld a, [hli]
	ld b, a
	jr z, .eastWestDivide
.northSouthDivide
	ld a, [wYCoord]
	jr .compareCoord
.eastWestDivide
	ld a, [wXCoord]

; この時点で hl = SplitMapSpriteSets の該当エントリの3バイト目のアドレス

; 境界線と自分の座標を比較して a に spriteSetIDを格納して return
.compareCoord
	cp b
	jr c, .loadSpriteSetID
	inc hl	; 東側 or 南側
.loadSpriteSetID
	ld a, [hl]
	ret

; Uses sprite set $01 for West side and $0A for East side.
; Route 20 is a special case because the two map sections have a more complex
; shape instead of the map simply being split horizontally or vertically.
.route20
	ld hl, wXCoord
	ld a, [hl]
	cp $2b
	ld a, $01
	ret c
	ld a, [hl]
	cp $3e
	ld a, $0a
	ret nc
	ld a, [hl]
	cp $37
	ld b, $08
	jr nc, .next
	ld b, $0d
.next
	ld a, [wYCoord]
	cp b
	ld a, $0a
	ret c
	ld a, $01
	ret

INCLUDE "data/sprite_sets.asm"
