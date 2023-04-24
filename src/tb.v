`default_nettype none
`timescale 1ns/1ps

/*
this testbench just instantiates the module and makes some convenient wires
that can be driven / tested by the cocotb test.py
*/

module tb (
    // testbench is controlled by test.py
    input clk,
    input rst,
    input result,
    input inputReady,
    input [4:0] inNibble,
    output [4:0] outNibble,
    output busy
   );

    // this part dumps the trace to a vcd file that can be viewed with GTKWave
    initial begin
        $dumpfile ("tb.vcd");
        $dumpvars (0, tb);
        #1;
    end

    // wire up the inputs and outputs
    wire [7:0] inputs = {inNibble[3], inNibble[2], inNibble[1], inNibble[0], inputReady, result, rst, clk};
    wire [7:0] outputs;
    assign busy = outputs[4]
    assign outNibble = outputs[3:0]

    // instantiate the DUT
    psychogenic_shaman psychogenic_shaman(
        `ifdef GL_TEST
            .vccd1( 1'b1),
            .vssd1( 1'b0),
        `endif
        .io_in  (inputs),
        .io_out (outputs)
        );

endmodule
