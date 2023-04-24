import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, Timer, ClockCycles

TestMessage = 'abcdppppefgh0000ijkl1111mnop2222qrst3333' * 5


def message_to_blocks(message: bytearray) -> bytearray:
    """Return a SHA-256 hash from the message passed.
    The argument should be a bytes, bytearray, or
    string object."""

    if isinstance(message, str):
        message = bytearray(message, 'ascii')
    elif isinstance(message, bytes):
        message = bytearray(message)
    elif not isinstance(message, bytearray):
        raise TypeError

    # Padding
    length = len(message) * 8 # len(message) is number of BYTES!!!
    message.append(0x80)
    while (len(message) * 8 + 64) % 512 != 0:
        message.append(0x00)

    message += length.to_bytes(8, 'big') # pad to 8 bytes or 64 bits

    assert (len(message) * 8) % 512 == 0, "Padding did not complete properly!"

    # Parsing
    blocks = [] # contains 512-bit chunks of message
    for i in range(0, len(message), 64): # 64 bytes is 512 bits
        blocks.append(message[i:i+64])
        
    return blocks


async def waitUntilReady(dut):
    while dut.busy.value:
        #dut._log.info("BZY")
        await ClockCycles(dut.clk, 1)
        

async def getResult(dut):
    dut.result.value = 1
    await ClockCycles(dut.clk, 2)
    res = []
    for _i in range((64)+1):
        v = dut.outNibble.value
        #dut._log.info(f'nibble: {hex(v)}')
        res.append(v)
        await ClockCycles(dut.clk, 1)
        
    dut.result.value = 0
    await ClockCycles(dut.clk, 1)
    return res

@cocotb.test()
async def test_sha(dut):
    dut._log.info("start")
    clock = Clock(dut.clk, 10, units="us")
    cocotb.start_soon(clock.start())

    dut._log.info("reset")
    dut.rst.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rst.value = 1
    dut.result.value = 0
    dut.inputReady.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rst.value = 0
    await ClockCycles(dut.clk, 10)
    
    message_blocks = message_to_blocks(TestMessage)
    for block in message_blocks:
        for c in block:
            for i in range(2):
                v = ((c & 0xf << ((1-i)*4)) >> ((1-i)*4))
                #print(f'NIBBLE {hex(v)}')
                await waitUntilReady(dut)
                dut.inNibble.value = v 
                await ClockCycles(dut.clk, 3)
                dut.inputReady.value = 1
                await ClockCycles(dut.clk, 10)
                dut.inputReady.value = 0
                await ClockCycles(dut.clk, 10)
        await ClockCycles(dut.clk, 20)
        await waitUntilReady(dut)
    
    await ClockCycles(dut.clk, 20)
    await waitUntilReady(dut)
    res = await getResult(dut)
    wholething = bytearray()
    for i in range(0, len(res)-1, 2):
        a = (int(res[i]) << 4) | int(res[i+1])
        wholething += int(a).to_bytes(1, 'big')
        
    asHex = wholething.hex()
    
    dut._log.info(f"SUM: {asHex}")
    # 5ed6690f5b59d80b1b403da500a51a6f3cafe14b8d32eda1913cdd7a31e4aaad
    assert(asHex.find('f5b59d80b1b403da500a51a6f3cafe14b8d32eda1913c') > 0)
    
    
    dut._log.info(res)


