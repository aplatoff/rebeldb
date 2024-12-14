	.section	__TEXT,__text,regular,pure_instructions
	.build_version macos, 15, 2
	.globl	_get
	.p2align	2
_get:
	.cfi_startproc
	sub	x8, x0, w1, uxtw
	ldrb	w8, [x8, #15]
	add	x8, x0, x8
	add	x0, x8, #2
	ret
	.cfi_endproc

	.globl	_push
	.p2align	2
_push:
	.cfi_startproc
	ldrb	w9, [x0]
	add	w8, w9, #1
	strb	w8, [x0]
	ldrb	w8, [x0, #1]
	mov	w10, #15
	sub	w9, w10, w9
	and	x9, x9, #0xff
	strb	w8, [x0, x9]
	add	x10, x0, x8
	mov	w9, w2
	add	x10, x10, #2
	cbz	x9, LBB1_2
LBB1_1:
	ldrb	w11, [x1], #1
	strb	w11, [x10], #1
	sub	x9, x9, #1
	cbnz	x9, LBB1_1
LBB1_2:
	add	w8, w8, w2
	strb	w8, [x0, #1]
	ret
	.cfi_endproc

.subsections_via_symbols
