* tee - T joint
*
* Itagaki Fumihiko 19-Jun-91  Create.
* Itagaki Fumihiko 19-Feb-93  Zap.
* 1.0
*
* Usage: tee [ -aiZ ] [ <ファイル> ] ...
*

.include doscall.h
.include chrcode.h

.xref DecodeHUPAIR
.xref issjis
.xref strlen
.xref strfor1
.xref strip_excessive_slashes

REQUIRED_OSVER	equ	$200			*  2.00以降

STACKSIZE	equ	2048

BUFSIZE		equ	8192

CTRLD	equ	$04
CTRLZ	equ	$1A

FLAG_a	equ	0
FLAG_Z	equ	1

.text

start:
		bra.s	start1
		dc.b	'#HUPAIR',0
start1:
		lea	stack(pc),a7
		lea	$10(a0),a0			*  A0 : PDBアドレス
		move.l	a7,d0
		sub.l	a0,d0
		move.l	d0,-(a7)
		move.l	a0,-(a7)
		DOS	_SETBLOCK
		addq.l	#8,a7
	*
		move.w	#-1,breakflag
		move.l	#-1,input
	*
	*  引数並び格納エリアを確保する
	*
		lea	1(a2),a0			*  A0 := コマンドラインの文字列の先頭アドレス
		bsr	strlen				*  D0.L := コマンドラインの文字列の長さ
		addq.l	#1,d0
		bsr	malloc
		bmi	insufficient_memory

		movea.l	d0,a1				*  A1 := 引数並び格納エリアの先頭アドレス
	*
	*  引数をデコードし，解釈する
	*
		bsr	DecodeHUPAIR
		movea.l	a1,a0				*  A0 : 引数ポインタ
		move.l	d0,d7				*  D7.L : 引数カウンタ
		moveq	#0,d6				*  D6.W : エラー・コード
		moveq	#0,d5				*  D5.L : フラグ
decode_opt_loop1:
		tst.l	d7
		beq	decode_opt_done

		cmpi.b	#'-',(a0)
		bne	decode_opt_done

		tst.b	1(a0)
		beq	decode_opt_done

		subq.l	#1,d7
		addq.l	#1,a0
		move.b	(a0)+,d0
		cmp.b	#'-',d0
		bne	decode_opt_loop2

		tst.b	(a0)+
		beq	decode_opt_done

		subq.l	#1,a0
decode_opt_loop2:
		cmp.b	#'i',d0
		beq	kill_break

		moveq	#FLAG_a,d1
		cmp.b	#'a',d0
		beq	set_option

		moveq	#FLAG_Z,d1
		cmp.b	#'Z',d0
		beq	set_option

		moveq	#1,d1
		tst.b	(a0)
		beq	bad_option_1

		bsr	issjis
		bne	bad_option_1

		moveq	#2,d1
bad_option_1:
		move.l	d1,-(a7)
		pea	-1(a0)
		move.w	#2,-(a7)
		lea	msg_illegal_option(pc),a0
		bsr	werror_myname_and_msg
		DOS	_WRITE
		lea	10(a7),a7
		lea	msg_usage(pc),a0
		bsr	werror
		moveq	#1,d6
		bra	exit_program

set_option:
		bset	d1,d5
set_option_done:
		move.b	(a0)+,d0
		bne	decode_opt_loop2
		bra	decode_opt_loop1

kill_break:
		DOS	_VERNUM
		cmp.w	#REQUIRED_OSVER,d0
		bcs	set_option_done

		moveq	#-1,d0
		bsr	breakck
		cmp.w	#2,d0
		beq	set_option_done

		move.w	d0,breakflag
		moveq	#2,d0
		bsr	breakck
		bra	set_option_done

breakck:
		move.w	d0,-(a7)
		DOS	_BREAKCK
		addq.l	#2,a7
		rts

decode_opt_done:
	*
	*  入力をオープンする
	*
		clr.w	-(a7)				*  標準入力を
		DOS	_DUP				*  複製したハンドルから入力し，
		addq.l	#2,a7
		move.l	d0,input
		bmi	open_fail

		clr.w	-(a7)				*  標準入力を
		DOS	_CLOSE				*  クローズする．
		addq.l	#2,a7				*  こうしないと ^C や ^S が効かない
	*
	*  出力デスクリプタテーブルを確保する
	*
		move.l	d7,d0				*  D7.L : 出力ファイル数-1
		addq.l	#1,d0
		lsl.l	#3,d0				*  x8
		bsr	malloc
		bmi	insufficient_memory

		move.l	d0,outputs
	*
	*  Open
	*
		movea.l	d0,a4
		move.l	#1,(a4)+			*  stdout
		clr.l	(a4)+
		move.l	d7,d1
		beq	open_file_done_all
open_file_loop:
		movea.l	a0,a1
		bsr	strfor1
		exg	a0,a1
		sf	d4				*  D4=0 : アペンドしない
		moveq	#1,d0				*  1 ... stdout
		cmpi.b	#'-',(a0)
		bne	open_file

		tst.b	1(a0)
		beq	file_ok_1
open_file:
		bsr	strip_excessive_slashes
		clr.w	-(a7)				*  まず読み込みモードで
		move.l	a0,-(a7)			*  出力先ファイルを
		DOS	_OPEN				*  オープンしてみる
		addq.l	#6,a7
		move.l	d0,d2
		bmi	do_create_file

		bsr	check_device
		and.w	#$80,d0				*  キャラクタデバイスかどうか
		move.w	d0,-(a7)
		move.w	d2,-(a7)
		DOS	_CLOSE
		addq.l	#2,a7
		tst.w	(a7)+				*  キャラクタ・デバイスならば
		bne	do_open_file			*  　オープンする（新規作成しない）

		btst	#FLAG_a,d5
		sne	d4				*  D4.B : アペンドフラグ  アペンドならば
		bne	do_open_file			*    オープンする（新規作成しない）
do_create_file:
		move.w	#$20,-(a7)			*  通常のファイルモードで
		move.l	a0,-(a7)			*  出力先ファイルを
		DOS	_CREATE				*  新規作成する
		bra	file_opened

do_open_file:
		move.w	#1,-(a7)			*  書き込みモードで
		move.l	a0,-(a7)			*  出力先ファイルを
		DOS	_OPEN				*  オープンする
file_opened:
		addq.l	#6,a7
file_ok_1:
		move.l	a0,d2
		tst.l	d0
		bpl	file_ok_2

		moveq	#2,d6
		bsr	werror_myname_and_msg
		move.l	a0,-(a7)
		lea	msg_create_fail(pc),a0
		bsr	werror
		movea.l	(a7)+,a0
		moveq	#-1,d0
file_ok_2:
		move.l	d0,(a4)+
		move.l	d2,(a4)+
		move.l	d0,d2
		bmi	open_file_done_one

		tst.b	d4
		beq	open_file_done_one

		bsr	check_device
		btst	#7,d0				* キャラクタ・デバイス
		bne	open_file_done_one		*   ならばシークしない

		move.w	#2,-(a7)			* EOF
		clr.l	-(a7)				* 　まで
		move.w	d2,-(a7)			* 　出力を
		DOS	_SEEK				* 　シークする
		addq.l	#8,a7
open_file_done_one:
		movea.l	a1,a0
		subq.l	#1,d1
		bne	open_file_loop
open_file_done_all:
	*
	*  Dump
	*
		btst	#FLAG_Z,d5
		sne	terminate_by_ctrlz
		sf	terminate_by_ctrld
		move.l	input,d0
		bsr	check_device
		btst	#7,d0				*  '0':block  '1':character
		beq	tee_start

		btst	#5,d0				*  '0':cooked  '1':raw
		bne	tee_start

		st	terminate_by_ctrlz
		st	terminate_by_ctrld
tee_start:
tee_loop:
		move.l	#BUFSIZE,-(a7)
		pea	buffer(pc)
		move.l	input,d0
		move.w	d0,-(a7)
		DOS	_READ
		lea	10(a7),a7
		move.l	d0,d3
		bmi	read_fail
.if 0
		beq	tee_done	* （ここで終わらなくても下で終わってくれる）
.endif

		sf	d4				* D4.B : EOF flag
		tst.b	terminate_by_ctrlz
		beq	trunc_ctrlz_done

		moveq	#CTRLZ,d0
		bsr	trunc
trunc_ctrlz_done:
		tst.b	terminate_by_ctrld
		beq	trunc_ctrld_done

		moveq	#CTRLD,d0
		bsr	trunc
trunc_ctrld_done:
		tst.l	d3
		beq	tee_done

		movea.l	outputs,a4
		move.l	d7,d1
write_loop:
		move.l	(a4),d0
		bmi	write_continue

		bsr	write_one
		bne	write_fail
write_continue:
		addq.l	#8,a4
		subq.l	#1,d1
		bcc	write_loop

		tst.b	d4
		beq	tee_loop
tee_done:
	*
	*  Close
	*
		movea.l	outputs,a4
		move.l	d7,d1
close_loop:
		move.l	(a4),d0
		cmp.w	#4,d0
		ble	close_continue

		move.w	d0,-(a7)
		DOS	_CLOSE
		addq.l	#2,a7
		tst.l	d0
		bmi	write_fail
close_continue:
		addq.l	#8,a4
		subq.l	#1,d1
		bcc	close_loop
	*
	*  exit
	*
exit_program:
		move.w	breakflag,d0
		bmi	exit_program_1

		bsr	breakck
exit_program_1:
		move.l	input,d0
		bmi	exit_program_2

		clr.w	-(a7)				*  標準入力を
		move.w	d0,-(a7)			*  元に
		DOS	_DUP2				*  戻す．
		DOS	_CLOSE				*  複製はクローズする．
exit_program_2:
		move.w	d6,-(a7)
		DOS	_EXIT2
*****************************************************************
trunc:
		move.l	d3,d1
		beq	trunc_done

		lea	buffer(pc),a3
		movea.l	a3,a2
trunc_find_loop:
		cmp.b	(a2)+,d0
		beq	trunc_found

		subq.l	#1,d1
		bne	trunc_find_loop
		bra	trunc_done

trunc_found:
		subq.l	#1,a2
		move.l	a2,d3
		sub.l	a3,d3
		st	d4				*  EOF detected
trunc_done:
		rts
*****************************************************************
write_one:
		move.l	d3,-(a7)
		pea	buffer(pc)
		move.w	d0,-(a7)
		DOS	_WRITE
		lea	10(a7),a7
		tst.l	d0
		bmi	write_one_return

		sub.l	d3,d0
		blt	write_one_return

		moveq	#0,d0
write_one_return:
		rts
*****************************************************************
insufficient_memory:
		lea	msg_no_memory(pc),a0
		bra	werror_exit_3
*****************************************************************
open_fail:
		lea	msg_open_fail(pc),a0
		bra	werror_exit_3
*****************************************************************
read_fail:
		lea	msg_read_fail(pc),a0
werror_exit_3:
		bsr	werror_myname_and_msg
		bra	exit_3
*****************************************************************
write_fail:
		move.l	4(a4),d0
		beq	write_fail_stdout

		movea.l	d0,a0
		bra	write_fail_1

write_fail_stdout:
		lea	word_stdout(pc),a0
write_fail_1:
		bsr	werror_myname_and_msg
		lea	msg_write_fail(pc),a0
		bsr	werror
exit_3:
		moveq	#3,d6
		bra	exit_program
*****************************************************************
werror_myname_and_msg:
		move.l	a0,-(a7)
		lea	msg_myname(pc),a0
		bsr	werror
		movea.l	(a7)+,a0
werror:
		movem.l	d0/a1,-(a7)
		movea.l	a0,a1
werror_1:
		tst.b	(a1)+
		bne	werror_1

		subq.l	#1,a1
		suba.l	a0,a1
		move.l	a1,-(a7)
		move.l	a0,-(a7)
		move.w	#2,-(a7)
		DOS	_WRITE
		lea	10(a7),a7
		movem.l	(a7)+,d0/a1
		rts
*****************************************************************
malloc:
		move.l	d0,-(a7)
		DOS	_MALLOC
		addq.l	#4,a7
		tst.l	d0
		rts
*****************************************************************
check_device:
		move.w	d0,-(a7)
		clr.w	-(a7)
		DOS	_IOCTRL
		addq.l	#4,a7
		rts
*****************************************************************
.data

	dc.b	0
	dc.b	'## tee 1.0 ##  Copyright(C)1991,93 by Itagaki Fumihiko',0

msg_myname:		dc.b	'tee: ',0
msg_no_memory:		dc.b	'メモリが足りません',CR,LF,0
msg_read_fail:		dc.b	'入力エラー',CR,LF,0
msg_open_fail:		dc.b	'標準入力をオープンできません',CR,LF,0
msg_create_fail:	dc.b	': 作成できません',CR,LF,0
msg_write_fail:		dc.b	': 出力エラー',CR,LF,0
msg_illegal_option:	dc.b	'不正なオプション -- ',0
msg_usage:		dc.b	CR,LF,'使用法:  tee [ -aiZ ] [ <ファイル> ] ...',CR,LF,0
word_stdout:		dc.b	'- 標準出力 -',0
*****************************************************************
.bss
.even
input:			ds.l	1
outputs:		ds.l	1
breakflag:		ds.w	1
terminate_by_ctrlz:	ds.b	1
terminate_by_ctrld:	ds.b	1
buffer:			ds.b	BUFSIZE

		ds.b	STACKSIZE
.even
stack:
*****************************************************************

.end start
