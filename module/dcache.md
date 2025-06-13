
# Entity: dcache 
- **File**: dcache.v

## Diagram
![Diagram](dcache.svg "Diagram")
## Generics

| Generic name | Type | Value | Description |
| ------------ | ---- | ----- | ----------- |
| DATA_WIDTH   |      | 32    |             |
| ADDR_WIDTH   |      | 32    |             |
| CACHE_SIZE   |      | 1024  |             |
| BLOCK_SIZE   |      | 16    |             |
| WRITE_POLICY |      | 0     |             |
| DEBUG        |      | 1     |             |
| HISTORY_SIZE |      | 4     |             |

## Ports

| Port name | Direction | Type             | Description |
| --------- | --------- | ---------------- | ----------- |
| clk       | input     |                  |             |
| rst_n     | input     |                  |             |
| cpu_req   | input     |                  |             |
| cpu_we    | input     |                  |             |
| cpu_addr  | input     | [ADDR_WIDTH-1:0] |             |
| cpu_wdata | input     | [DATA_WIDTH-1:0] |             |
| cpu_ready | output    |                  |             |
| cpu_rdata | output    | [DATA_WIDTH-1:0] |             |
| cpu_hit   | output    |                  |             |
| mem_req   | output    |                  |             |
| mem_we    | output    |                  |             |
| mem_addr  | output    | [ADDR_WIDTH-1:0] |             |
| mem_wdata | output    | [DATA_WIDTH-1:0] |             |
| mem_ready | input     |                  |             |
| mem_rdata | input     | [DATA_WIDTH-1:0] |             |

## Signals

| Name                   | Type                                                                                                                                                  | Description |
| ---------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------- | ----------- |
| history_ptr [NUM_SETS] | logic [3:0]                                                                                                                                           |             |
| state                  | enum logic [1:0] {<br><span style="padding-left:20px">IDLE,<br><span style="padding-left:20px"> WRITE_BACK,<br><span style="padding-left:20px"> FILL} |             |
| next_state             | enum logic [1:0] {<br><span style="padding-left:20px">IDLE,<br><span style="padding-left:20px"> WRITE_BACK,<br><span style="padding-left:20px"> FILL} |             |
| tag                    | logic [TAG_BITS-1:0]                                                                                                                                  |             |
| index                  | logic [INDEX_BITS-1:0]                                                                                                                                |             |
| offset                 | logic [OFFSET_BITS-1:0]                                                                                                                               |             |
| way_hits               | logic [NUM_WAYS-1:0]                                                                                                                                  |             |
| hit                    | logic                                                                                                                                                 |             |
| way_idx                | integer                                                                                                                                               |             |
| current_way            | integer                                                                                                                                               |             |
| i                      | integer                                                                                                                                               |             |
| j                      | integer                                                                                                                                               |             |

## Constants

| Name        | Type | Value                             | Description |
| ----------- | ---- | --------------------------------- | ----------- |
| NUM_WAYS    |      | 4                                 |             |
| NUM_SETS    |      | CACHE_SIZE/(BLOCK_SIZE*NUM_WAYS)  |             |
| OFFSET_BITS |      | (BLOCK_SIZE)                      |             |
| INDEX_BITS  |      | (NUM_SETS)                        |             |
| TAG_BITS    |      | ADDR_WIDTH-INDEX_BITS-OFFSET_BITS |             |

## Types

| Name            | Type                                                                                                                                                                                                                                                                                                                                                                                                                                          | Description |
| --------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------- |
| cache_line_t    | struct packed {<br><span style="padding-left:20px">          logic valid;<br><span style="padding-left:20px">                          logic dirty;<br><span style="padding-left:20px">                          logic [TAG_BITS-1:0] tag;<br><span style="padding-left:20px">             logic [DATA_WIDTH-1:0] data;<br><span style="padding-left:20px">           logic [1:0] access_type;<br><span style="padding-left:20px">          } |             |
| history_entry_t | struct packed {<br><span style="padding-left:20px">          logic [TAG_BITS-1:0] tag;<br><span style="padding-left:20px">             logic [INDEX_BITS-1:0] index;<br><span style="padding-left:20px">           logic valid;<br><span style="padding-left:20px">                      }                                                                                                                                                    |             |
| lru_bits_t      | logic [NUM_WAYS*NUM_WAYS-1:0]                                                                                                                                                                                                                                                                                                                                                                                                                 |             |

## Functions
- find_lru_way <font id="function_arguments">(logic [NUM_WAYS*NUM_WAYS-1:0] lru)</font> <font id="function_return">return (integer)</font>
- update_lru <font id="function_arguments">(lru_bits_t lru,<br><span style="padding-left:20px"> input integer way)</font> <font id="function_return">return (lru_bits_t)</font>
- detect_pattern <font id="function_arguments">(input history_entry_t history[HISTORY_SIZE)</font> <font id="function_return">return (logic [1:0])</font>
- select_victim <font id="function_arguments">(input cache_line_t ways[N)</font> <font id="function_return">return (integer)</font>

## Processes
- unnamed: (  )
  - **Type:** always_comb
- unnamed: ( @(posedge clk or negedge rst_n) )
  - **Type:** always_ff
