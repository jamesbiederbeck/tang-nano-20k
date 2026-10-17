// Minimal LED blinker for the Tang Nano 20K (27 MHz clock on pin 4).
module blink (
    input  wire clk,
    output wire [5:0] leds
);
    reg [24:0] count = 0;
    always @(posedge clk) count <= count + 1;
    assign leds = ~count[24:19];  // LEDs are active low
endmodule
