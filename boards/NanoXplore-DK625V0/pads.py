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
p.addPad('switch_i[4]'       ,{'location':'IOB10_D04N'  , 'standard':'LVCMOS', 'drive':'16mA'}) # NA09 (Switch S5)
p.addPad('switch_i[5]'       ,{'location':'IOB10_D09N'  , 'standard':'LVCMOS', 'drive':'16mA'}) # NA04 (Switch S6)

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
p.addPad('led_o[0]'          ,{'location':'IOB0_D01P'   , 'standard':'LVCMOS', 'drive':'16mA'}) # LED1
p.addPad('led_o[1]'          ,{'location':'IOB0_D03N'   , 'standard':'LVCMOS', 'drive':'16mA'}) # LED2
p.addPad('led_o[2]'          ,{'location':'IOB0_D03P'   , 'standard':'LVCMOS', 'drive':'16mA'}) # LED3
p.addPad('led_o[3]'          ,{'location':'IOB1_D05N'   , 'standard':'LVCMOS', 'drive':'16mA'}) # LED4
p.addPad('led_o[4]'          ,{'location':'IOB1_D05P'   , 'standard':'LVCMOS', 'drive':'16mA'}) # LED5
p.addPad('led_o[5]'          ,{'location':'IOB1_D06N'   , 'standard':'LVCMOS', 'drive':'16mA'}) # LED6
p.addPad('led_o[6]'          ,{'location':'IOB1_D06P'   , 'standard':'LVCMOS', 'drive':'16mA'}) # LED7
p.addPad('led_o[7]'          ,{'location':'IOB1_D02N'   , 'standard':'LVCMOS', 'drive':'16mA'}) # LED8
p.addPad('led_o[8]'          ,{'location':'USER_D0'     }) # USER_* have predefined parameters
p.addPad('led_o[9]'          ,{'location':'USER_D1'     }) # USER_* have predefined parameters
p.addPad('led_o[10]'         ,{'location':'USER_D2'     }) # USER_* have predefined parameters
p.addPad('led_o[11]'         ,{'location':'USER_D3'     }) # USER_* have predefined parameters
p.addPad('led_o[12]'         ,{'location':'USER_D4'     }) # USER_* have predefined parameters
p.addPad('led_o[13]'         ,{'location':'USER_D5'     }) # USER_* have predefined parameters
p.addPad('led_o[14]'         ,{'location':'USER_D6'     }) # USER_* have predefined parameters
p.addPad('led_o[15]'         ,{'location':'USER_D7'     }) # USER_* have predefined parameters
p.addPad('led_o[16]'         ,{'location':'USER_CS_N'   }) # USER_* have predefined parameters
p.addPad('led_o[17]'         ,{'location':'USER_WE_N'   }) # USER_* have predefined parameters
p.addPad('led_o[18]'         ,{'location':'USER_DATA_OE'}) # USER_* have predefined parameters

#------------------------------------------------------------------
# SPI Flash
#------------------------------------------------------------------
p.addPad('spi_sclk_o'        ,{'location':'USER_D9'     }) # USER_* have predefined parameters
p.addPad('spi_cs_b_o'        ,{'location':'USER_D8'     }) # USER_* have predefined parameters
p.addPad('spi_mosi_o'        ,{'location':'USER_D11'    }) # USER_* have predefined parameters
p.addPad('spi_miso_i'        ,{'location':'USER_D10'    }) # USER_* have predefined parameters
                                                        
# Bank5 spare I/Os                                      
p.addPad('debug_uart_tx_o'   ,{'location':'IOB5_D05P'   , 'standard':'LVCMOS', 'drive':'16mA'}) # 2 from left
#                             {'location':'IOB5_D05N'   , 'standard':'LVCMOS', 'drive':'16mA'}) # 3 from left
p.addPad('uart_rts_b_o'      ,{'location':'IOB5_D01P'   , 'standard':'LVCMOS', 'drive':'16mA'}) # 4 from left
p.addPad('uart_cts_b_i'      ,{'location':'IOB5_D01N'   , 'standard':'LVCMOS', 'drive':'16mA', 'weakTermination':'PullDown'}) # 5 from left
p.addPad('uart_tx_o'         ,{'location':'IOB5_D03P'   , 'standard':'LVCMOS', 'drive':'16mA'}) # 6 from left
p.addPad('uart_rx_i'         ,{'location':'IOB5_D03N'   , 'standard':'LVCMOS', 'drive':'16mA'}) # 7 from left
                                                        
# Bank0 spare I/Os                                        
p.addPad('debug_o[0]'        ,{'location':'IOB0_D06P'   , 'standard':'LVCMOS', 'drive':'16mA'}) # 1 from left 2  from bottom
p.addPad('debug_o[1]'        ,{'location':'IOB0_D07P'   , 'standard':'LVCMOS', 'drive':'16mA'}) # 1 from left 3  from bottom
p.addPad('debug_o[2]'        ,{'location':'IOB0_D05P'   , 'standard':'LVCMOS', 'drive':'16mA'}) # 1 from left 4  from bottom
p.addPad('debug_o[3]'        ,{'location':'IOB0_D09P'   , 'standard':'LVCMOS', 'drive':'16mA'}) # 1 from left 5  from bottom
#                             {'location':'IOB0_D01N'   , 'standard':'LVCMOS', 'drive':'16mA'}) # 1 from left 6  from bottom
#                             {'location':'IOB0_D08P'   , 'standard':'LVCMOS', 'drive':'16mA'}) # 1 from left 7  from bottom
#                             {'location':'IOB0_D10N'   , 'standard':'LVCMOS', 'drive':'16mA'}) # 1 from left 8  from bottom
#                             {'location':'IOB0_D02N'   , 'standard':'LVCMOS', 'drive':'16mA'}) # 1 from left 9  from bottom
#                             {'location':'IOB0_D04N'   , 'standard':'LVCMOS', 'drive':'16mA'}) # 1 from left 10 from bottom
p.addPad('debug_o[4]'        ,{'location':'IOB0_D06N'   , 'standard':'LVCMOS', 'drive':'16mA'}) # 2 from left 2  from bottom
p.addPad('debug_o[5]'        ,{'location':'IOB0_D07N'   , 'standard':'LVCMOS', 'drive':'16mA'}) # 2 from left 3  from bottom
p.addPad('debug_o[6]'        ,{'location':'IOB0_D05N'   , 'standard':'LVCMOS', 'drive':'16mA'}) # 2 from left 4  from bottom
p.addPad('debug_o[7]'        ,{'location':'IOB0_D09N'   , 'standard':'LVCMOS', 'drive':'16mA'}) # 2 from left 5  from bottom
#                             {'location':'IOB0_D11N'   , 'standard':'LVCMOS', 'drive':'16mA'}) # 2 from left 6  from bottom
#                             {'location':'IOB0_D08N'   , 'standard':'LVCMOS', 'drive':'16mA'}) # 2 from left 7  from bottom
#                             {'location':'IOB0_D02P'   , 'standard':'LVCMOS', 'drive':'16mA'}) # 2 from left 8  from bottom
#                             {'location':'IOB0_D04P'   , 'standard':'LVCMOS', 'drive':'16mA'}) # 2 from left 9  from bottom

# Bank12 spare I/Os
p.addPad('debug_mux_i[0]'    ,{'location':'IOB12_D10P'  , 'standard':'LVCMOS', 'drive':'16mA', 'weakTermination':'PullUp'}) # 1 from left 2  from bottom
p.addPad('debug_mux_i[1]'    ,{'location':'IOB12_D05P'  , 'standard':'LVCMOS', 'drive':'16mA', 'weakTermination':'PullUp'}) # 1 from left 3  from bottom
p.addPad('debug_mux_i[2]'    ,{'location':'IOB12_D07N'  , 'standard':'LVCMOS', 'drive':'16mA', 'weakTermination':'PullUp'}) # 1 from left 4  from bottom
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
