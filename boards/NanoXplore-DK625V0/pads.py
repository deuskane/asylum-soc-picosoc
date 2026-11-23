#------------------------------------------------------------------
# Clock Sources
#------------------------------------------------------------------
p.addPad('clk_i'             ,{'location':'IOB12_D09P', 'standard':'LVCMOS', 'drive':'16mA'}) # clock oscillator
                             
#------------------------------------------------------------------
# Switch
#------------------------------------------------------------------
p.addPad('switch_i[0]'       ,{'location':'IOB10_D04P'  , 'standard':'LVCMOS', 'drive':'16mA'}) # PA04 (Switch S4)
p.addPad('switch_i[1]'       ,{'location':'IOB10_D03N'  , 'standard':'LVCMOS', 'drive':'16mA'}) # NA03 (Switch S3)
p.addPad('switch_i[2]'       ,{'location':'IOB10_D03P'  , 'standard':'LVCMOS', 'drive':'16mA'}) # PA03 (Switch S2)
p.addPad('switch_i[3]'       ,{'location':'IOB10_D09P'  , 'standard':'LVCMOS', 'drive':'16mA'}) # PA09 (Switch S1)
# Function of the UART pads (S6 S5) : 00 user UART, 01 HWLA UART, 10 JTAG, 11 JTAG over the UART
p.addPad('debug_mux_sel_i[0]',{'location':'IOB10_D04N'  , 'standard':'LVCMOS', 'drive':'16mA'}) # NA09 (Switch S5)
p.addPad('debug_mux_sel_i[1]',{'location':'IOB10_D09N'  , 'standard':'LVCMOS', 'drive':'16mA'}) # NA04 (Switch S6)

#------------------------------------------------------------------
# Push Buttons
#------------------------------------------------------------------
p.addPad('arst_i'            ,{'location':'IOB10_D12N'  , 'standard':'LVCMOS', 'drive':'16mA'}) # NA12 (Pushbutton S11)
p.addPad('it_user_i'         ,{'location':'IOB10_D14P'  , 'standard':'LVCMOS', 'drive':'16mA'}) # PA14 (Pushbutton S12)
p.addPad('inject_error_i[0]' ,{'location':'IOB10_D07P'  , 'standard':'LVCMOS', 'drive':'16mA'}) # PA07 (Pushbutton S8) 
p.addPad('inject_error_i[1]' ,{'location':'IOB10_D12P'  , 'standard':'LVCMOS', 'drive':'16mA'}) # PA12 (Pushbutton S9) 
p.addPad('inject_error_i[2]' ,{'location':'IOB10_D07N'  , 'standard':'LVCMOS', 'drive':'16mA'}) # NA07 (Pushbutton S10)

#------------------------------------------------------------------
# User LEDs
#------------------------------------------------------------------
p.addPad('led0_o[0]'          ,{'location':'IOB0_D01P'   , 'standard':'LVCMOS', 'drive':'16mA'}) # LED1
p.addPad('led0_o[1]'          ,{'location':'IOB0_D03N'   , 'standard':'LVCMOS', 'drive':'16mA'}) # LED2
p.addPad('led0_o[2]'          ,{'location':'IOB0_D03P'   , 'standard':'LVCMOS', 'drive':'16mA'}) # LED3
p.addPad('led0_o[3]'          ,{'location':'IOB1_D05N'   , 'standard':'LVCMOS', 'drive':'16mA'}) # LED4
p.addPad('led0_o[4]'          ,{'location':'IOB1_D05P'   , 'standard':'LVCMOS', 'drive':'16mA'}) # LED5
p.addPad('led0_o[5]'          ,{'location':'IOB1_D06N'   , 'standard':'LVCMOS', 'drive':'16mA'}) # LED6
p.addPad('led0_o[6]'          ,{'location':'IOB1_D06P'   , 'standard':'LVCMOS', 'drive':'16mA'}) # LED7
p.addPad('led0_o[7]'          ,{'location':'IOB1_D02N'   , 'standard':'LVCMOS', 'drive':'16mA'}) # LED8
p.addPad('led_diff_o[0]'      ,{'location':'USER_D0'     }) # USER_* have predefined parameters
p.addPad('led_diff_o[1]'      ,{'location':'USER_D1'     }) # USER_* have predefined parameters
p.addPad('led_diff_o[2]'      ,{'location':'USER_D2'     }) # USER_* have predefined parameters
p.addPad('led1_o[0]'          ,{'location':'USER_D3'     }) # USER_* have predefined parameters
p.addPad('led1_o[1]'          ,{'location':'USER_D4'     }) # USER_* have predefined parameters
p.addPad('led1_o[2]'          ,{'location':'USER_D5'     }) # USER_* have predefined parameters
p.addPad('led1_o[3]'          ,{'location':'USER_D6'     }) # USER_* have predefined parameters
p.addPad('led1_o[4]'          ,{'location':'USER_D7'     }) # USER_* have predefined parameters
p.addPad('led1_o[5]'          ,{'location':'USER_CS_N'   }) # USER_* have predefined parameters
p.addPad('led1_o[6]'          ,{'location':'USER_WE_N'   }) # USER_* have predefined parameters
p.addPad('led1_o[7]'          ,{'location':'USER_DATA_OE'}) # USER_* have predefined parameters

#------------------------------------------------------------------
# SPI Flash
#------------------------------------------------------------------
# Only SCLK, CS#, MOSI (spi_io_io[0]) and MISO (spi_io_io[1]) are wired : USER_SPI_NB_IO=2
p.addPad('spi_sclk_io'       ,{'location':'USER_D9'     }) # USER_* have predefined parameters
p.addPad('spi_cs_b_io'       ,{'location':'USER_D8'     }) # USER_* have predefined parameters
p.addPad('spi_io_io[0]'      ,{'location':'USER_D11'    }) # USER_* have predefined parameters (MOSI)
p.addPad('spi_io_io[1]'      ,{'location':'USER_D10'    }) # USER_* have predefined parameters (MISO)
                                                        
# Bank5 spare I/Os                                      
p.addPad('debug_uart_tx_o'   ,{'location':'IOB5_D05P'   , 'standard':'LVCMOS', 'drive':'16mA'}) # 2 from left
#                             {'location':'IOB5_D05N'   , 'standard':'LVCMOS', 'drive':'16mA'}) # 3 from left
# UART pads, shared with the HWLA UART and JTAG (debug_mux_sel_i), FTDI MPSSE
# pinout : rx = TCK (AD0), tx = TDI (AD1, pull-up : TDI idle high), cts_b =
# TDO (AD2, pull-down : CTS* active without a cable), rts_b = TMS (AD3,
# pull-up : TMS idle high)
p.addPad('uart_rts_b_io'     ,{'location':'IOB5_D01P'   , 'standard':'LVCMOS', 'drive':'16mA', 'weakTermination':'PullUp'}) # 4 from left
p.addPad('uart_cts_b_io'     ,{'location':'IOB5_D01N'   , 'standard':'LVCMOS', 'drive':'16mA', 'weakTermination':'PullDown'}) # 5 from left
p.addPad('uart_tx_io'        ,{'location':'IOB5_D03P'   , 'standard':'LVCMOS', 'drive':'16mA', 'weakTermination':'PullUp'}) # 6 from left
p.addPad('uart_rx_i'         ,{'location':'IOB5_D03N'   , 'standard':'LVCMOS', 'drive':'16mA'}) # 7 from left
                                                        
# Bank0 spare I/Os (I2C : open drain, weak pull-ups of the pads, external
# pull-ups expected on the I2C bus)
p.addPad('i2c_scl_io'        ,{'location':'IOB0_D06P'   , 'standard':'LVCMOS', 'drive':'16mA', 'weakTermination':'PullUp'}) # 1 from left 2  from bottom (I2C SCL, open drain)
p.addPad('i2c_sda_io'        ,{'location':'IOB0_D07P'   , 'standard':'LVCMOS', 'drive':'16mA', 'weakTermination':'PullUp'}) # 1 from left 3  from bottom (I2C SDA, open drain)
p.addPad('pwm_o'             ,{'location':'IOB0_D05P'   , 'standard':'LVCMOS', 'drive':'16mA'}) # 1 from left 4  from bottom (PWM)
#                             {'location':'IOB0_D09P'   , 'standard':'LVCMOS', 'drive':'16mA'}) # 1 from left 5  from bottom
#                             {'location':'IOB0_D01N'   , 'standard':'LVCMOS', 'drive':'16mA'}) # 1 from left 6  from bottom
#                             {'location':'IOB0_D08P'   , 'standard':'LVCMOS', 'drive':'16mA'}) # 1 from left 7  from bottom
#                             {'location':'IOB0_D10N'   , 'standard':'LVCMOS', 'drive':'16mA'}) # 1 from left 8  from bottom
#                             {'location':'IOB0_D02N'   , 'standard':'LVCMOS', 'drive':'16mA'}) # 1 from left 9  from bottom
#                             {'location':'IOB0_D04N'   , 'standard':'LVCMOS', 'drive':'16mA'}) # 1 from left 10 from bottom
#                             {'location':'IOB0_D06N'   , 'standard':'LVCMOS', 'drive':'16mA'}) # 2 from left 2  from bottom
#                             {'location':'IOB0_D07N'   , 'standard':'LVCMOS', 'drive':'16mA'}) # 2 from left 3  from bottom
#                             {'location':'IOB0_D05N'   , 'standard':'LVCMOS', 'drive':'16mA'}) # 2 from left 4  from bottom
#                             {'location':'IOB0_D09N'   , 'standard':'LVCMOS', 'drive':'16mA'}) # 2 from left 5  from bottom
#                             {'location':'IOB0_D11N'   , 'standard':'LVCMOS', 'drive':'16mA'}) # 2 from left 6  from bottom
#                             {'location':'IOB0_D08N'   , 'standard':'LVCMOS', 'drive':'16mA'}) # 2 from left 7  from bottom
#                             {'location':'IOB0_D02P'   , 'standard':'LVCMOS', 'drive':'16mA'}) # 2 from left 8  from bottom
#                             {'location':'IOB0_D04P'   , 'standard':'LVCMOS', 'drive':'16mA'}) # 2 from left 9  from bottom

# Bank12 spare I/Os
#                             {'location':'IOB12_D10P'  , 'standard':'LVCMOS', 'drive':'16mA', 'weakTermination':'PullUp'}) # 1 from left 2  from bottom
#                             {'location':'IOB12_D05P'  , 'standard':'LVCMOS', 'drive':'16mA', 'weakTermination':'PullUp'}) # 1 from left 3  from bottom
#                             {'location':'IOB12_D07N'  , 'standard':'LVCMOS', 'drive':'16mA', 'weakTermination':'PullUp'}) # 1 from left 4  from bottom
#                             {'location':'IOB12_D08N'  , 'standard':'LVCMOS', 'drive':'16mA'} # 1 from left 5  from bottom
#                             {'location':'IOB12_D11P'  , 'standard':'LVCMOS', 'drive':'16mA'} # 1 from left 6  from bottom
#                             {'location':'IOB12_D06P'  , 'standard':'LVCMOS', 'drive':'16mA'} # 1 from left 7  from bottom
#                             {'location':'IOB12_D10N'  , 'standard':'LVCMOS', 'drive':'16mA'} # 2 from left 2  from bottom
#                             {'location':'IOB12_D05N'  , 'standard':'LVCMOS', 'drive':'16mA'} # 2 from left 3  from bottom
#                             {'location':'IOB12_D07P'  , 'standard':'LVCMOS', 'drive':'16mA'} # 2 from left 4  from bottom
#                             {'location':'IOB12_D09N'  , 'standard':'LVCMOS', 'drive':'16mA'} # 2 from left 5  from bottom
#                             {'location':'IOB12_D11N'  , 'standard':'LVCMOS', 'drive':'16mA'} # 2 from left 6  from bottom
#                             {'location':'IOB12_D06N'  , 'standard':'LVCMOS', 'drive':'16mA'} # 2 from left 7  from bottom

# Banks definition
p.addBank('IOB0'  ,{'voltage':'3.3'})
p.addBank('IOB1'  ,{'voltage':'3.3'})
p.addBank('IOB2'  ,{'voltage':'2.5'})
p.addBank('IOB3'  ,{'voltage':'2.5'})
p.addBank('IOB4'  ,{'voltage':'2.5'})
p.addBank('IOB5'  ,{'voltage':'3.3'})
p.addBank('IOB6'  ,{'voltage':'2.5'})
p.addBank('IOB7'  ,{'voltage':'2.5'})
p.addBank('IOB8'  ,{'voltage':'2.5'})
p.addBank('IOB9'  ,{'voltage':'2.5'})
p.addBank('IOB10' ,{'voltage':'1.8'})
p.addBank('IOB11' ,{'voltage':'1.8'})
p.addBank('IOB12' ,{'voltage':'3.3'})
