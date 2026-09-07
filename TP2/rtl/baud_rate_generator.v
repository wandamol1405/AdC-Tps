module baud_rate_generator #(
    parameter BAUD_RATE = 19200,
    parameter OVERSAMPLE = 16,
    parameter CLK_FREQ = 100000000
) (
    input wire clk,
    input wire reset,
    output reg s_tick
);

    localparam integer BAUD_DIV = CLK_FREQ / (BAUD_RATE * OVERSAMPLE);
    localparam integer BAUD_DIV_WIDTH = $clog2(BAUD_DIV);

    reg [BAUD_DIV_WIDTH-1:0] counter;

    always @(posedge clk) begin
        if (reset) begin // Synchronous reset
            counter <= 0;
            s_tick <= 0;
        end else begin
            if (counter == BAUD_DIV - 1) begin
                counter <= 0;
                s_tick <= 1;
            end else begin
                counter <= counter + 1;
                s_tick <= 0;
            end
        end
    end
    
endmodule