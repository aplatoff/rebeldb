	.section	__TEXT,__text,regular,pure_instructions
	.build_version macos, 15, 2
	.globl	_get
	.p2align	2
_get:
	.cfi_startproc
	ubfiz	x8, x1, #1, #15
	sub	x8, x0, x8
	mov	w9, #65534
	ldrh	w8, [x8, x9]
	add	x8, x0, x8
	add	x0, x8, #4
	ret
	.cfi_endproc

	.globl	_push
	.p2align	2
_push:
	.cfi_startproc
	ldrh	w8, [x0, #2]
	ldrh	w9, [x0]
	sub	x9, x0, x9, lsl #1
	mov	w10, #65534
	strh	w8, [x9, x10]
	mov	w9, w2
	add	x10, x8, #4
	cbz	x9, LBB1_2
LBB1_1:
	ldrb	w11, [x1], #1
	strb	w11, [x0, x10]
	add	x10, x10, #1
	sub	x9, x9, #1
	cbnz	x9, LBB1_1
LBB1_2:
	add	w8, w8, w2
	strh	w8, [x0, #2]
	ldrh	w8, [x0]
	add	w8, w8, #1
	strh	w8, [x0]
	ret
	.cfi_endproc

	.globl	_alloc
	.p2align	2
_alloc:
	.cfi_startproc
	ldrh	w8, [x0]
	ldrh	w9, [x0, #2]
	sub	x10, x0, w8, uxtw #1
	mov	w11, #65534
	strh	w9, [x10, x11]
	add	w9, w9, w1
	strh	w9, [x0, #2]
	ldrh	w9, [x0]
	add	w9, w9, #1
	strh	w9, [x0]
	mov	x0, x8
	ret
	.cfi_endproc

	.globl	_available
	.p2align	2
_available:
	.cfi_startproc
	ldrh	w8, [x0, #2]
	ldrh	w9, [x0]
	add	w8, w8, w9, lsl #1
	mov	w9, #-6
	sub	w8, w9, w8
	and	w0, w8, #0xffff
	ret
	.cfi_endproc

.subsections_via_symbols
