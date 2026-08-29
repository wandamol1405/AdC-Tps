module reg_bank #(
    parameter WIDTH = 8 // Number of bits for the register
) (
    input wire clk,
    input wire reset,
    input wire [WIDTH-1:0] i_data,
    input wire i_load_reg,
    output reg [WIDTH-1:0] o_data
);

    always @(posedge clk) begin
        if (reset) begin
            o_data <= {WIDTH{1'b0}};
        end else if (i_load_reg) begin
            o_data <= i_data;
        end
    end
    
endmodule