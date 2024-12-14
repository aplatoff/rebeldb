	.section	__TEXT,__text,regular,pure_instructions
	.build_version macos, 15, 2
	.globl	_heapAlloc
	.p2align	2
_heapAlloc:
	.cfi_startproc
	sub	sp, sp, #176
	stp	x28, x27, [sp, #80]
	stp	x26, x25, [sp, #96]
	stp	x24, x23, [sp, #112]
	stp	x22, x21, [sp, #128]
	stp	x20, x19, [sp, #144]
	stp	x29, x30, [sp, #160]
	.cfi_def_cfa_offset 176
	.cfi_offset w30, -8
	.cfi_offset w29, -16
	.cfi_offset w19, -24
	.cfi_offset w20, -32
	.cfi_offset w21, -40
	.cfi_offset w22, -48
	.cfi_offset w23, -56
	.cfi_offset w24, -64
	.cfi_offset w25, -72
	.cfi_offset w26, -80
	.cfi_offset w27, -88
	.cfi_offset w28, -96
	mov	x21, x30
	mov	x22, x2
	mov	x23, x1
	mov	x19, x0
	ldr	x8, [x0, #48]
	xpaci	x21
	cbz	x8, LBB0_4
	ldr	x9, [x19, #40]
	ldr	x20, [x9]
	cbz	x20, LBB0_4
	ldrh	w10, [x20, #6]
	ldrh	w11, [x20, #4]
	add	w10, w10, w11, lsl #1
	mov	w11, #-10
	sub	w10, w11, w10
	cmp	w22, w10, uxth
	b.ls	LBB0_20
	add	x28, sp, #16
	b	LBB0_5
LBB0_4:
	add	x28, sp, #32
LBB0_5:
	ldp	x0, x8, [x19, #80]
	ldr	x8, [x8]
	mov	w1, #65536
	mov	w2, #2
	mov	x3, x21
	blr	x8
	cbz	x0, LBB0_18
	mov	x20, x0
	ldr	x8, [x19, #8]
	stp	w8, wzr, [x0]
	ldp	x8, x27, [x19, #8]
	cmp	x27, x8
	b.hi	LBB0_17
	mov	x24, x27
LBB0_8:
	lsr	x9, x24, #1
	add	x9, x9, #8
	adds	x9, x24, x9
	csinv	x24, x9, xzr, lo
	cmp	x24, x8
	b.ls	LBB0_8
	mov	x25, x19
	ldr	x8, [x25], #24
	str	x8, [sp, #8]
	lsl	x26, x27, #3
	cbz	x27, LBB0_12
	lsr	x8, x24, #61
	cmp	x8, #0
	cset	w8, ne
	strb	w8, [sp, #64]
	b.ne	LBB0_12
	lsl	x4, x24, #3
	ldp	x0, x8, [x19, #24]
	ldr	x8, [x8, #8]
	ldr	x1, [sp, #8]
	mov	x2, x26
	mov	w3, #3
	mov	x5, x21
	blr	x8
	tbnz	w0, #0, LBB0_16
LBB0_12:
	ldr	q0, [x25]
	str	q0, [sp, #48]
	add	x8, sp, #64
	add	x0, sp, #48
	mov	x1, x24
	mov	x2, x21
	bl	_mem.Allocator.allocWithSizeAndAlignment__anon_1477
	ldrh	w8, [sp, #72]
	cbnz	w8, LBB0_19
	ldr	x25, [sp, #64]
	ldp	x1, x8, [x19]
	lsl	x2, x8, #3
	mov	x0, x25
	bl	_memcpy
	cmp	x27, #0
	csel	x2, xzr, x26, eq
	mov	x8, #-6148914691236517206
	ldr	x9, [sp, #8]
	csel	x1, x8, x9, eq
	cbz	x2, LBB0_15
	ldp	x0, x8, [x19, #24]
	ldr	x8, [x8, #16]
	mov	w3, #3
	mov	x4, x21
	blr	x8
LBB0_15:
	str	x25, [x19]
LBB0_16:
	str	x24, [x19, #16]
	ldr	x8, [x19, #8]
LBB0_17:
	add	x9, x8, #1
	str	x9, [x19, #8]
	ldr	x9, [x19]
	str	x20, [x9, x8, lsl #3]
	strh	wzr, [x28, #8]
	str	x20, [x28]
	b	LBB0_30
LBB0_18:
	mov	w8, #1
LBB0_19:
	strh	w8, [x28, #8]
	b	LBB0_49
LBB0_20:
	add	x8, x9, x8, lsl #3
	ldur	x8, [x8, #-8]
	str	x8, [x9]
	ldr	x8, [x19, #48]
	subs	x8, x8, #1
	str	x8, [x19, #48]
	b.eq	LBB0_30
	mov	x26, #0
	ldr	x8, [x19, #40]
	ldr	x24, [x8]
LBB0_22:
	cmp	x26, #0
	cset	w8, lt
	strb	w8, [sp, #64]
	b.lt	LBB0_28
	mov	w28, #1
	bfi	x28, x26, #1, #63
	ldp	x27, x8, [x19, #40]
	cmp	x28, x8
	b.hs	LBB0_29
	lsl	x9, x26, #1
	add	x25, x9, #2
	cmp	x25, x8
	b.hs	LBB0_26
	ldr	x0, [x27, x25, lsl #3]
	ldr	x1, [x27, x28, lsl #3]
	bl	_mem.PageManager.cmpFree
	and	w8, w0, #0x3
	cmp	w8, #1
	csel	x28, x25, x28, eq
LBB0_26:
	ldr	x25, [x27, x28, lsl #3]
	mov	x0, x24
	mov	x1, x25
	bl	_mem.PageManager.cmpFree
	and	w8, w0, #0x3
	cmp	w8, #1
	b.eq	LBB0_29
	str	x25, [x27, x26, lsl #3]
	mov	x26, x28
	b	LBB0_22
LBB0_28:
	ldr	x27, [x19, #40]
LBB0_29:
	str	x24, [x27, x26, lsl #3]
LBB0_30:
	mov	x9, x20
	ldrh	w10, [x9, #4]!
	ldrh	w8, [x9, #2]
	sub	x9, x9, x10, lsl #1
	mov	w10, #65530
	strh	w8, [x9, x10]
	mov	w9, w22
	add	x10, x8, #8
	cbz	x9, LBB0_32
LBB0_31:
	ldrb	w11, [x23], #1
	strb	w11, [x20, x10]
	add	x10, x10, #1
	sub	x9, x9, #1
	cbnz	x9, LBB0_31
LBB0_32:
	add	w8, w8, w22
	strh	w8, [x20, #6]
	ldrh	w8, [x20, #4]
	add	w8, w8, #1
	strh	w8, [x20, #4]
	ldp	x9, x8, [x19, #48]
	cmp	x8, x9
	b.ls	LBB0_34
	ldr	x8, [x19, #40]
	b	LBB0_45
LBB0_34:
	mov	x22, x8
LBB0_35:
	add	x10, x22, x22, lsr #1
	add	x22, x10, #8
	cmp	x22, x9
	b.ls	LBB0_35
	ldp	x24, x28, [x19, #64]
	cbz	x8, LBB0_42
	ldr	x23, [x19, #40]
	lsr	x9, x22, #61
	cmp	x9, #0
	cset	w9, ne
	strb	w9, [sp, #32]
	b.ne	LBB0_49
	lsl	x26, x8, #3
	lsl	x25, x22, #3
	ldr	x8, [x28, #8]
	bl	_OUTLINED_FUNCTION_0
	mov	x4, x25
	mov	x5, x21
	blr	x8
	tbnz	w0, #0, LBB0_41
	ldr	x8, [x28]
	mov	x0, x24
	mov	x1, x25
	mov	w2, #3
	mov	x3, x21
	blr	x8
	cbz	x0, LBB0_49
	mov	x27, x0
	cmp	x25, x26
	csel	x2, x25, x26, lo
	mov	x1, x23
	bl	_memcpy
	ldr	x8, [x28, #16]
	bl	_OUTLINED_FUNCTION_0
	mov	x4, x21
	blr	x8
	mov	x23, x27
LBB0_41:
	and	x8, x22, #0x1fffffffffffffff
	cmp	x25, #0
	csel	x22, xzr, x8, eq
	mov	x8, #-6148914691236517206
	csel	x8, x8, x23, eq
	b	LBB0_44
LBB0_42:
	stp	x24, x28, [sp, #48]
	add	x8, sp, #64
	add	x0, sp, #48
	mov	x1, x22
	mov	x2, x21
	bl	_mem.Allocator.allocWithSizeAndAlignment__anon_1477
	ldrh	w8, [sp, #72]
	cbnz	w8, LBB0_49
	ldr	x8, [sp, #64]
LBB0_44:
	str	x8, [x19, #40]
	str	x22, [x19, #56]
	ldr	x9, [x19, #48]
LBB0_45:
	add	x10, x9, #1
	str	x10, [x19, #48]
	str	x20, [x8, x9, lsl #3]
	ldp	x22, x8, [x19, #40]
	sub	x23, x8, #1
	ldr	x20, [x22, x23, lsl #3]
	cbz	x23, LBB0_48
LBB0_46:
	sub	x8, x23, #1
	lsr	x24, x8, #1
	ldr	x21, [x22, x24, lsl #3]
	mov	x0, x20
	mov	x1, x21
	bl	_mem.PageManager.cmpFree
	and	w8, w0, #0x3
	cmp	w8, #1
	b.ne	LBB0_48
	str	x21, [x22, x23, lsl #3]
	ldr	x22, [x19, #40]
	mov	x23, x24
	cbnz	x24, LBB0_46
LBB0_48:
	str	x20, [x22, x23, lsl #3]
LBB0_49:
	ldp	x29, x30, [sp, #160]
	ldp	x20, x19, [sp, #144]
	ldp	x22, x21, [sp, #128]
	ldp	x24, x23, [sp, #112]
	ldp	x26, x25, [sp, #96]
	ldp	x28, x27, [sp, #80]
	add	sp, sp, #176
	ret
	.cfi_endproc

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
	ldrh	w9, [x0]
	ldrh	w8, [x0, #2]
	sub	x9, x0, x9, lsl #1
	mov	w10, #65534
	strh	w8, [x9, x10]
	mov	w9, w2
	add	x10, x8, #4
	cbz	x9, LBB2_2
LBB2_1:
	ldrb	w11, [x1], #1
	strb	w11, [x0, x10]
	add	x10, x10, #1
	sub	x9, x9, #1
	cbnz	x9, LBB2_1
LBB2_2:
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

	.p2align	2
_mem.PageManager.cmpFree:
	.cfi_startproc
	ldrh	w8, [x0, #6]
	ldrh	w9, [x0, #4]
	add	w8, w8, w9, lsl #1
	and	w9, w8, #0xffff
	mov	w10, #-10
	sub	w8, w10, w8
	and	w8, w8, #0xffff
	ldrh	w11, [x1, #6]
	ldrh	w12, [x1, #4]
	add	w11, w11, w12, lsl #1
	sub	w10, w10, w11
	cmp	w8, w10, uxth
	cset	w8, lo
	cmp	w9, w11, uxth
	mov	w9, #2
	csel	w0, w9, w8, eq
	ret
	.cfi_endproc

	.p2align	2
_mem.Allocator.allocWithSizeAndAlignment__anon_1477:
	.cfi_startproc
	sub	sp, sp, #48
	stp	x20, x19, [sp, #16]
	stp	x29, x30, [sp, #32]
	.cfi_def_cfa_offset 48
	.cfi_offset w30, -8
	.cfi_offset w29, -16
	.cfi_offset w19, -24
	.cfi_offset w20, -32
	mov	x19, x8
	lsr	x8, x1, #61
	cmp	x8, #0
	cset	w8, ne
	strb	w8, [sp, #8]
	b.ne	LBB6_4
	lsl	x1, x1, #3
	cbz	x1, LBB6_5
	mov	x3, x2
	ldp	x0, x8, [x0]
	ldr	x8, [x8]
	mov	w2, #3
	blr	x8
	cbz	x0, LBB6_6
	mov	w8, #0
	b	LBB6_7
LBB6_4:
Lloh0:
	adrp	x8, l___unnamed_1@PAGE
Lloh1:
	add	x8, x8, l___unnamed_1@PAGEOFF
Lloh2:
	ldr	q0, [x8]
	str	q0, [x19]
	b	LBB6_8
LBB6_5:
	mov	w8, #0
	strh	wzr, [sp, #4]
	str	wzr, [sp]
	mov	x0, #-8
	b	LBB6_7
LBB6_6:
	strh	wzr, [sp, #4]
	str	wzr, [sp]
	mov	w8, #1
LBB6_7:
	str	x0, [x19]
	strh	w8, [x19, #8]
	ldr	w8, [sp]
	stur	w8, [x19, #10]
	ldrh	w8, [sp, #4]
	strh	w8, [x19, #14]
LBB6_8:
	ldp	x29, x30, [sp, #32]
	ldp	x20, x19, [sp, #16]
	add	sp, sp, #48
	ret
	.loh AdrpAddLdr	Lloh0, Lloh1, Lloh2
	.cfi_endproc

	.p2align	2
_OUTLINED_FUNCTION_0:
	.cfi_startproc
	mov	x0, x24
	mov	x1, x23
	mov	x2, x26
	mov	w3, #3
	ret
	.cfi_endproc

	.section	__TEXT,__literal16,16byte_literals
	.p2align	3, 0x0
l___unnamed_2:
	.quad	-8
	.short	0
	.space	6

	.p2align	3, 0x0
l___unnamed_1:
	.space	8
	.short	1
	.space	6

.subsections_via_symbols
