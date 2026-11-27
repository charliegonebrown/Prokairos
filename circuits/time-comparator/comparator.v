// 32-bit unsigned >= comparator for TapeSynth
// Input: 64 bits (a[31:0] = current block, b[31:0] = target block), LSB first
// Output: 1 bit (1 if a >= b)
module comparator(
  input  [31:0] a,
  input  [31:0] b,
  output        out
);
  assign out = (a >= b);
endmodule
