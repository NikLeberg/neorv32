/* ################################################################################################# */
/* # << NEORV32 - park_loop.S - Execution-Based On-Chip Debugger Firmware - Park Loop Code >>      # */
/* # ********************************************************************************************* # */
/* # BSD 3-Clause License                                                                          # */
/* #                                                                                               # */
/* # Copyright (c) 2023, Stephan Nolting. All rights reserved.                                     # */
/* #                                                                                               # */
/* # Redistribution and use in source and binary forms, with or without modification, are          # */
/* # permitted provided that the following conditions are met:                                     # */
/* #                                                                                               # */
/* # 1. Redistributions of source code must retain the above copyright notice, this list of        # */
/* #    conditions and the following disclaimer.                                                   # */
/* #                                                                                               # */
/* # 2. Redistributions in binary form must reproduce the above copyright notice, this list of     # */
/* #    conditions and the following disclaimer in the documentation and/or other materials        # */
/* #    provided with the distribution.                                                            # */
/* #                                                                                               # */
/* # 3. Neither the name of the copyright holder nor the names of its contributors may be used to  # */
/* #    endorse or promote products derived from this software without specific prior written      # */
/* #    permission.                                                                                # */
/* #                                                                                               # */
/* # THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS   # */
/* # OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF               # */
/* # MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE    # */
/* # COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,     # */
/* # EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE # */
/* # GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED    # */
/* # AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING     # */
/* # NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED  # */
/* # OF THE POSSIBILITY OF SUCH DAMAGE.                                                            # */
/* # ********************************************************************************************* # */
/* # The NEORV32 Processor - https://github.com/stnolting/neorv32              (c) Stephan Nolting # */
/* ################################################################################################# */

// debug module (DM) address map
.equ DM_CODE_BASE, 0xffffff00 // base address of debug_module's code ROM (park loop)
.equ DM_PBUF_BASE, 0xffffff80 // base address of debug_module's program buffer (PBUF)
.equ DM_DATA_BASE, 0xffffffA0 // base address of debug_module's abstract data buffer (DATA)
.equ DM_SREG_BASE, 0xffffffC0 // base address of debug_module's status register

// status register (SREG) word offsets
.equ SREG_HLT_ACK, 0x0 // -/w: CPU has halted in debug mode and is waiting in park loop
.equ SREG_RES_REQ, 0x4 // r/-: DM requests to resume
.equ SREG_RES_ACK, 0x4 // -/w: CPU starts to resume
.equ SREG_EXE_REQ, 0x8 // r/-: DM requests to execute program buffer
.equ SREG_EXE_ACK, 0x8 // -/w: CPU starts to execute program buffer
.equ SREG_EXC_ACK, 0xC // -/w: CPU has detected an exception while in debug-mode

.file	"park_loop.S"
.section .text
.balign 4
.option norvc
.global __start
.global entry_exception
.global entry_normal

__start:

// BASE + 0: exception entry - signal EXCEPTION condition to DM and restart parking loop
entry_exception:
  csrr    x9,   mhartid                           // convert hartid to bit position
  li      x8,   0x1
  sll     x9,   x8, x9
  sw      x9,   (DM_SREG_BASE+SREG_EXC_ACK)(zero) // trigger exception-acknowledge to inform DM
  ebreak                                          // re-enter debug mode (at "entry_normal" entry point)

// BASE + 0x14: normal entry - ebreak in debug-mode, halt request or return from single-stepped instruction
entry_normal:
  csrw    dscratch0, x8                           // backup x8 and x9 to dscratch so we have two GPRs available
  csrw    dscratch1, x9

// polling loop - waiting for requests
park_loop:
  csrr    x9,   mhartid                           // convert hartid to bit position
  li      x8,   0x1
  sll     x9,   x8, x9
  sw      x9,   (DM_SREG_BASE+SREG_HLT_ACK)(zero) // ACK that CPU is halted
  lw      x8,   (DM_SREG_BASE+SREG_EXE_REQ)(zero) // request to execute program buffer?
  and     x8,   x8, x9
  bnez    x8,   execute
  lw      x8,   (DM_SREG_BASE+SREG_RES_REQ)(zero) // request to resume?
  and     x8,   x8, x9
  beqz    x8,   park_loop

// resume normal operation
resume:
  sw      x9,   (DM_SREG_BASE+SREG_RES_ACK)(zero) // ACK that CPU is about to resume
                                                  // x9 still contains hartid as bit position
  csrr    x8,   dscratch0                         // restore x8 from dscratch0
  csrr    x9,   dscratch1                         // restore x9 from dscratch1
  dret                                            // exit debug mode

// execute program buffer
execute:
  sw      x9,   (DM_SREG_BASE+SREG_EXE_ACK)(zero) // ACK that execution is about to start
                                                  // x9 still contains hartid as bit position
  csrr    x8,   dscratch0                         // restore x8 from dscratch0
  csrr    x9,   dscratch1                         // restore x9 from dscratch1
  fence.i                                         // synchronize i-cache and prefetch with memory (PBUF)
  jalr    zero, zero, %lo(DM_PBUF_BASE)           // jump to beginning of program buffer (PBUF)

// fill remaining ROM space with instructions that cause a debug-mode-internal exception
unused:
  ecall                                           // should never be reached
  ecall
  ecall
  ecall
  ecall
  ecall
