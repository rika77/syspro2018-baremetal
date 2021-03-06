/*
 *            boot.S
 * written by Shinichi Awamoto, 2017
 * 
 * 仮想メモリの設定、IA-32eモードへの移行、C言語コードへの踏み台
 */
 
#define ASM_FILE
#include "multiboot2.h"

#define MULTIBOOTHEADER_SIZE (multibootheader_end - multibootheader_start)

.global entry
.global multiboot_info
.global gdt_desc
.global gdtr
.code32
.section .bootstrap

.balign 8

.globl pml4t
  
multibootheader_start:
  .long MULTIBOOT2_HEADER_MAGIC
  .long MULTIBOOT_ARCHITECTURE_I386
  .long MULTIBOOTHEADER_SIZE
  .long -(MULTIBOOT2_HEADER_MAGIC + MULTIBOOT_ARCHITECTURE_I386 + MULTIBOOTHEADER_SIZE)

  // multiboot tags
  // 8バイト境界にアラインされていること
  // 参考： multiboot2 specification 3.1.3 General tag structure

  .balign 8
align_tag:  
  // 参考： multiboot2 specification 3.1.11 Module alignment tag
  .short MULTIBOOT_HEADER_TAG_MODULE_ALIGN
  .short 0
  .long 8

  .balign 8
framebuffer_tag:  
  // 参考： multiboot2 specification 3.1.10 The framebuffer tag of Multiboot2 header
  .short MULTIBOOT_HEADER_TAG_FRAMEBUFFER
  .short 0
  .long  20
  .long 1024
  .long 768
  .long 32

  .balign 8
end_tag:
  .short MULTIBOOT_HEADER_TAG_END
  .short 0
  .long 8
  
multibootheader_end:

.text
entry:
  // この時点で既に32bitプロテクトモード
  cli

  movl %ebx, (multiboot_info)

  movl $(initial_stack_buffer + 0x1000), %esp

  // PML4Tをセット
	movl $pml4t, %edi
  movl %edi, %cr3

  //
  // ページテーブルの構築
  //

  // PML4Tの第一エントリはPDPT1を指す
  movl $pml4t, %edi
  movl $pdpt1, %eax
  orl  $((1 << 0) | (1 << 1) | (1 << 2)), %eax
  movl %eax, (%edi)
  movl $0, 4(%edi)

  // PDPT1に0-1GB, 2GB-4GBストレートマップする
  movl $pdpt1, %edi
  movl $pd1, %eax
  orl  $((1 << 0) | (1 << 1) | (1 << 2)), %eax
  movl %eax, (%edi)
  movl $0, 4(%edi)
  
  movl $pd2, %eax
  orl  $((1 << 0) | (1 << 1) | (1 << 2)), %eax
  movl %eax, 16(%edi)
  movl $0, 20(%edi)

  movl $pd3, %eax
  orl  $((1 << 0) | (1 << 1) | (1 << 2)), %eax
  movl %eax, 24(%edi)
  movl $0, 28(%edi)

  movl $pd1, %edi
  mov  $0x00000000, %eax
  call setup_1G_table

  movl $pd2, %edi
  mov  $0x80000000, %eax
  call setup_1G_table

  movl $pd3, %edi
  mov  $0xC0000000, %eax
  call setup_1G_table

  // ページテーブルの構築はここまで

  // PAE&PGE&PSEビットを立てる
  movl %cr4, %eax
  orl  $((1 << 4) | (1 << 5) | (1 << 7)), %eax
  movl %eax, %cr4

  //
  // IA-32eモードへの移行
  //

  // LMビットを立てる
  movl $0xC0000080, %ecx
  rdmsr
  orl  $(1 << 8), %eax
  wrmsr

  // PG&PE bitを立てる
  movl %cr0, %eax
	orl  $((1 << 31) | (1 << 0)), %eax
	andl $(~((1 << 30) | (1 << 29))), %eax
  movl %eax, %cr0
  lgdt gdtr
  ljmp $0x10, $entry64

setup_1G_table:
  mov $0, %ecx
setup_1G_table_loop:
  orl  $((1 << 0) | (1 << 1) | (1 << 2) | (1 << 7)), %eax
  mov %eax, (%edi)
  inc %ecx
  cmp $512, %ecx
  je  setup_1G_table_end
  add $8, %edi
  add $0x200000, %eax
  jmp setup_1G_table_loop
setup_1G_table_end:
  ret

.code64
entry64:
  // IA-32eモード
  movl $0x18, %eax
  movw %ax, %ds
  movw %ax, %es
  movw %ax, %fs
  movw %ax, %gs
  movw %ax, %ss
  movq $(initial_stack_buffer + 0x1000), %rsp
  call cmain

loop: 
  hlt
  jmp loop

.data 
.balign 8
gdt_desc:
  // null descriptor
  .quad 0
  .quad 0
  .quad 0x00209a0000000000  // code descriptor
  .quad 0x0000920000000000  // data descriptor
  
  .word 0
gdtr:
  .word 8*4 - 1
  .quad gdt_desc

.bss
.balign 4096  
initial_stack_buffer:
  .skip 4096

pml4t:
  .skip 4096

pdpt1:
  .skip 4096

pd1:
  .skip 4096

pd2:
  .skip 4096

pd3:
  .skip 4096

