import logging
from pymodbus.client.sync import ModbusSerialClient

# === Enable pymodbus debug logging ===
logging.basicConfig()
log = logging.getLogger()
log.setLevel(logging.INFO)  # Change to logging.INFO to reduce verbosity

def modbus_connect(port: str, baudrate: int, parity: str = 'N') -> ModbusSerialClient:
    log.info(f"Connecting to Modbus RTU on port={port}, baudrate={baudrate}, parity={parity}")
    client = ModbusSerialClient(
        method   = 'rtu',
        port     = port,
        baudrate = baudrate,
        stopbits = 1,
        bytesize = 8,
        parity   = parity,
        timeout  = 2,
        rtscts   = 1
    )
    if not client.connect():
        raise ConnectionError(f"Failed to connect to serial port {port}")
    log.info("Connection established.")
    return client

def modbus_read(client: ModbusSerialClient, slave_id: int, address: int, count: int = 1):
    log.info(f"Function 3: Reading {count} register(s) from address 0x{address:04X} (slave ID: 0x{slave_id:02X})")
    result = client.read_holding_registers(address=address, count=count, unit=slave_id)
    if result.isError():
        log.error(f"Modbus error: {result}")
        log.error(f"Error reading registers at address 0x{address:04X}")
        return None
    log.debug(f"Raw response object: {result}")
    for register in result.registers:
        log.info(f"[0x{address:04X}] : 0x{register:04X}")
        address+=1
    return result.registers

def modbus_write(client: ModbusSerialClient, slave_id: int, address: int, value: int):
    log.info(f"Function 6: Writing value 0x{value:04X} to address 0x{address:04X} (slave ID: 0x{slave_id:02X})")
    result = client.write_register(address=address, value=value, unit=slave_id)
    if result.isError():
        log.debug(f"Modbus error: {result}")
        log.error(f"Error writing value to address 0x{address:04X}")
        return False
    log.debug(f"Raw response object: {result}")
    log.info(f"Successfully wrote value 0x{value:04X} to address 0x{address:04X}")
    return True

# === Example usage ===
if __name__ == "__main__":
    try:
        port_name = '/dev/ttyUSB0'  # Replace with your actual serial port
        baudrate  = 9600
        parity    = 'N'  # Options: 'N', 'E', 'O', 'M', 'S'
        slave_id  = 0x5A

        client    = modbus_connect(port=port_name, baudrate=baudrate, parity=parity)

        modbus_write (client, slave_id=slave_id, address=0x0020, value=0x003C)
        modbus_read  (client, slave_id=slave_id, address=0x0020, count=1)
        modbus_read  (client, slave_id=slave_id, address=0x0010, count=1)

        #while True:
        #    res = modbus_read  (client, slave_id=slave_id, address=0x0010, count=1)
        #    modbus_write (client, slave_id=slave_id, address=0x0020, value=res[0])            

        
    except Exception as e:
        log.error(f"[ERROR] {e}")
    finally:
        if 'client' in locals():
            client.close()
            log.info("Modbus client connection closed.")
