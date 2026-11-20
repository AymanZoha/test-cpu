/*
 * Nibble-sized 4-bit CPU
 * Copyright (c) 2026 Ayman Ishraq Zoha
 * SPDX-License-Identifier: Apache-2.0
 *
 * A tiny accumulator CPU. One instruction runs per clock cycle.
 *
 * Registers
 *   A   4-bit accumulator: every ALU result lands here (shown on uo_out[3:0])
 *   B   4-bit helper register
 *   PC  4-bit program counter: the ADDRESS of the next instruction (16 slots)
 *   C   carry flag  (set by ADD/SUB)
 *   Z   zero flag   (set when an ALU result is 0)
 *
 * Instruction format (8 bits):  [7:4] opcode   [3:0] immediate value "k"
 *
 *   op  name   what it does
 *   0   NOP    nothing
 *   1   LDI k  A = k
 *   2   ADDI k A = A + k        (sets C, Z)
 *   3   SUBI k A = A - k        (C = 1 means no borrow, sets Z)
 *   4   ANDI k A = A & k        (sets Z)
 *   5   ORI  k A = A | k        (sets Z)
 *   6   XORI k A = A ^ k        (sets Z)
 *   7   ADDB   A = A + B        (sets C, Z)
 *   8   SUBB   A = A - B        (C = 1 means no borrow, sets Z)
 *   9   MOVB   B = A
 *   A   SWAP   A <-> B          (sets Z from new A)
 *   B   JMP k  PC = k
 *   C   JZ  k  if Z, PC = k
 *   D   JC  k  if C, PC = k
 *   E   NOT    A = ~A           (sets Z)
 *   F   HLT    stop until reset
 *
 * Where instructions come from
 *   uio[7] = 0  -> built-in demo program (Fibonacci) from on-chip ROM
 *   uio[7] = 1  -> external memory: chip puts PC on uio[3:0], you feed the
 *                  instruction at that address into ui_in[7:0]
 */

`default_nettype none

module tt_um_aymanzoha_cpu4 (
    input  wire [7:0] ui_in,    // instruction from external memory
    output wire [7:0] uo_out,   // A, flags, halted
    input  wire [7:0] uio_in,   // uio[7] = external program select
    output wire [7:0] uio_out,  // uio[3:0] = PC (address bus)
    output wire [7:0] uio_oe,   // 1 = pin is an output
    input  wire       ena,      // always 1 when powered
    input  wire       clk,
    input  wire       rst_n     // low = reset
);

  // ---------------------------------------------------------------- state
  reg [3:0] A, B, PC;
  reg       C, Z, halted;

  // ---------------------------------------------------------------- fetch
  // Built-in demo: Fibonacci 1,1,2,3,5,8,13 then restart when it overflows.
  reg [7:0] rom_data;
  always @(*) begin
    case (PC)
      4'd0:    rom_data = 8'h11;  // LDI 1
      4'd1:    rom_data = 8'h90;  // MOVB      (B = 1)
      4'd2:    rom_data = 8'h10;  // LDI 0     (A = 0)
      4'd3:    rom_data = 8'h70;  // ADDB      (A = A + B, next Fibonacci number)
      4'd4:    rom_data = 8'hD0;  // JC 0      (overflowed past 15? start again)
      4'd5:    rom_data = 8'hA0;  // SWAP
      4'd6:    rom_data = 8'hB3;  // JMP 3
      default: rom_data = 8'h00;  // NOP
    endcase
  end

  wire       use_ext = uio_in[7];
  wire [7:0] instr   = use_ext ? ui_in : rom_data;

  // --------------------------------------------------------------- decode
  wire [3:0] op = instr[7:4];
  wire [3:0] k  = instr[3:0];

  // ------------------------------------------------------------------ ALU
  // Which number goes into the ALU's second input: k or B (a multiplexer!)
  wire [3:0] operand = (op == 4'h7 || op == 4'h8) ? B : k;

  // 5-bit results so the carry out of bit 3 lands in bit 4
  wire [4:0] sum  = {1'b0, A} + {1'b0, operand};
  wire [4:0] diff = {1'b0, A} + {1'b0, ~operand} + 5'd1;  // A - x = A + (~x) + 1

  // ------------------------------------------------------------- execute
  always @(posedge clk) begin
    if (!rst_n) begin
      A <= 4'd0;  B <= 4'd0;  PC <= 4'd0;
      C <= 1'b0;  Z <= 1'b0;  halted <= 1'b0;
    end else if (!halted) begin
      PC <= PC + 4'd1;                       // default: go to the next address
      case (op)
        4'h1: A <= k;
        4'h2, 4'h7: begin A <= sum[3:0];  C <= sum[4];  Z <= (sum[3:0]  == 0); end
        4'h3, 4'h8: begin A <= diff[3:0]; C <= diff[4]; Z <= (diff[3:0] == 0); end
        4'h4: begin A <= A & k;  Z <= ((A & k) == 0); end
        4'h5: begin A <= A | k;  Z <= ((A | k) == 0); end
        4'h6: begin A <= A ^ k;  Z <= ((A ^ k) == 0); end
        4'h9: B <= A;
        4'hA: begin A <= B; B <= A; Z <= (B == 0); end
        4'hB: PC <= k;
        4'hC: if (Z) PC <= k;
        4'hD: if (C) PC <= k;
        4'hE: begin A <= ~A; Z <= (~A == 4'd0); end
        4'hF: begin halted <= 1'b1; PC <= PC; end
        default: ;                           // NOP
      endcase
    end
  end

  // ------------------------------------------------------------- outputs
  assign uo_out  = {1'b0, halted, Z, C, A};
  assign uio_out = {4'b0000, PC};
  assign uio_oe  = 8'b0000_1111;             // uio[3:0] out, uio[7:4] in

  wire _unused = &{ena, uio_in[6:0], 1'b0};

endmodule
