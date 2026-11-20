## How it works

A tiny 4-bit accumulator CPU that runs one instruction per clock cycle.

- **A**: 4-bit accumulator, where every ALU result goes (shown on `uo[3:0]`)
- **B**: 4-bit helper register
- **PC**: 4-bit program counter, the address of the next instruction (16 addresses)
- **C / Z**: carry and zero flags

Each instruction is 8 bits: the top 4 bits are the opcode, the bottom 4 bits are an immediate value `k`.

| Op | Name | Action |
|----|------|--------|
| 0 | NOP | nothing |
| 1 | LDI k | A = k |
| 2 | ADDI k | A = A + k (sets C, Z) |
| 3 | SUBI k | A = A − k (C = 1 means no borrow, sets Z) |
| 4 | ANDI k | A = A AND k (sets Z) |
| 5 | ORI k | A = A OR k (sets Z) |
| 6 | XORI k | A = A XOR k (sets Z) |
| 7 | ADDB | A = A + B (sets C, Z) |
| 8 | SUBB | A = A − B (sets C, Z) |
| 9 | MOVB | B = A |
| A | SWAP | swap A and B (sets Z) |
| B | JMP k | PC = k |
| C | JZ k | jump to k if Z |
| D | JC k | jump to k if C |
| E | NOT | A = NOT A (sets Z) |
| F | HLT | stop until reset |

## How to test

**Built-in demo:** keep `uio[7]` low, reset, and clock the chip slowly (a few Hz). The LEDs on `uo[3:0]` count through the Fibonacci numbers 1, 1, 2, 3, 5, 8, 13. When the next number overflows 4 bits, the program restarts.

**Your own program:** pull `uio[7]` high. The chip outputs the PC on `uio[3:0]`. Put the instruction stored at that address onto `ui[7:0]` (from DIP switches, a microcontroller, or a ROM) before the next rising clock edge.

## External hardware

None needed for the demo. The LEDs on the Tiny Tapeout demo board are enough to watch it run.
