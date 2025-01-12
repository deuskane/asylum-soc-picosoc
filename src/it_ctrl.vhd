library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity it_ctrl is
  port (
    clk_i   : in  std_logic;
    arstn_i : in  std_logic;
    it_i    : in  std_logic;
    it_val_o: out std_logic;
    it_ack_i: in  std_logic
    );
end it_ctrl;

architecture rtl of it_ctrl is

  signal it       : std_logic;
  signal it_r     : std_logic;
  signal it_val_r : std_logic;

begin

  it <= it_i and not it_r;

  p_it_val_r: process (clk_i, arstn_i) is
  begin  -- process p_it_val_r
    if arstn_i = '0' then                 -- asynchronous reset (active low)
      it_r     <= '0';
      it_val_r <= '0';
      
    elsif clk_i'event and clk_i = '1' then  -- rising clock edge
      it_r <= it_i;
      
      if it_ack_i = '1' then
        it_val_r <= '0';
      elsif it = '1' then
        it_val_r <= '1';
      end if;
    end if;
  end process p_it_val_r;

  it_val_o <= it_val_r;
  
end architecture rtl;
    
  
