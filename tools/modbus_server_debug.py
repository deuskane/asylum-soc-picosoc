import serial
import struct
import time

DEBUG = True  # Set to False to disable debug output

def debug(msg):
    if DEBUG:
        print(f"[DEBUG] {msg}")

def crc16(data: bytes) -> bytes:
    """Compute Modbus RTU CRC16 (LSB first)"""
    crc = 0xFFFF
    for byte in data:
        crc ^= byte
        for _ in range(8):
            if crc & 0x0001:
                crc >>= 1
                crc ^= 0xA001
            else:
                crc >>= 1
    crc_bytes = struct.pack('<H', crc)
    debug(f"CRC16: {crc_bytes.hex()} for data: {data.hex()}")
    return crc_bytes

def build_modbus_frame(slave_id: int, function_code: int, payload: bytes) -> bytes:
    frame = struct.pack('B', slave_id) + struct.pack('B', function_code) + payload
    crc = crc16(frame)
    full_frame = frame + crc
    debug(f"Built frame: {full_frame.hex()}")
    return full_frame

def send_modbus_request(serial_port: serial.Serial, frame: bytes) -> bytes:
    debug(f"Sending frame: {frame.hex()}")
    serial_port.write(frame)
    time.sleep(0.5)  # Wait for response
    response = serial_port.read(256)
    debug(f"Received raw response: {response.hex()}")
    return response

def read_holding_registers(serial_port, slave_id, address, count):
    payload = struct.pack('>HH', address, count)
    frame = build_modbus_frame(slave_id, 0x03, payload)
    response = send_modbus_request(serial_port, frame)

    if len(response) < 5:
        debug("Response too short.")
        return None

    byte_count = response[2]
    debug(f"Byte count: {byte_count}")

    if len(response) < 3 + byte_count + 2:
        debug("Incomplete response.")
        return None

    values = []
    for i in range(count):
        start = 3 + i * 2
        reg_bytes = response[start:start+2]
        value = struct.unpack('>H', reg_bytes)[0]
        debug(f"Register {address + i}: {reg_bytes.hex()} -> {value}")
        values.append(value)

    return values

def write_single_register(serial_port, slave_id, address, value):
    payload = struct.pack('>HH', address, value)
    frame = build_modbus_frame(slave_id, 0x06, payload)
    response = send_modbus_request(serial_port, frame)

    if response[:6] == frame[:6]:
        debug("Write confirmed.")
        return True
    else:
        debug("Write failed or unexpected response.")
        return False

# Example usage
if __name__ == "__main__":
    try:
        port = serial.Serial(
            port='/dev/ttyUSB0',
            baudrate=9600,
            bytesize=8,
            parity='N',
            stopbits=1,
            timeout=1
        )
        
        slave_id = 0x5A

        # Read from address 0x0064
        #read_holding_registers(port, slave_id, address=0x0064, count=1)

        # Write value 0x04D2 to address 0x0065
        write_single_register(port, slave_id, address=0x0020, value=0x0001)

    except Exception as e:
        print(f"[ERROR] {e}")
    finally:
        if 'port' in locals() and port.is_open:
            port.close()
