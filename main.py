import time
import random
import math
from pythonosc import udp_client

# --- OSC Client Configuration ---
OSC_HOST = "127.0.0.1"  # Godot is running on the same machine
OSC_PORT = 9001

# Create an OSC client to send messages
client = udp_client.SimpleUDPClient(OSC_HOST, OSC_PORT)

# --- Simulation Parameters ---
# Alpha Amplitude: Simulates the power of the alpha brainwave.
# High amplitude means a calm, focused state, leading to a high, stable fountain arch.
# Low amplitude means a less focused state, leading to a low, challenging arch.
MIN_AMPLITUDE = 0.2
MAX_AMPLITUDE = 1.0

# Alpha Frequency (IAF): Simulates the Individual Alpha Frequency.
# This controls the speed of the waves traveling along the fountain arch.
# A typical range is 8-12 Hz.
MIN_FREQUENCY = 8.0  # Hz
MAX_FREQUENCY = 12.0 # Hz

# --- Main Loop ---
def main():
    """
    Simulates EEG alpha wave data (amplitude and frequency)
    and sends it to Godot via OSC.
    """
    print(f"Streaming simulated EEG data to {OSC_HOST}:{OSC_PORT}...")
    print("Press Ctrl+C to stop.")

    # Simulate a smoothly changing signal over time
    time_elapsed = 0.0

    while True:
        try:
            # Use sine waves to create smoothly fluctuating values for realism
            # The frequencies are chosen to be non-repeating to create complex behavior
            amplitude_osc = (math.sin(time_elapsed * 0.1) + 1) / 2  # Oscillates between 0 and 1
            frequency_osc = (math.sin(time_elapsed * 0.23) + 1) / 2 # Oscillates between 0 and 1

            # Map the oscillating values to our desired min/max ranges
            alpha_amplitude = MIN_AMPLITUDE + (amplitude_osc * (MAX_AMPLITUDE - MIN_AMPLITUDE))
            alpha_frequency = MIN_FREQUENCY + (frequency_osc * (MAX_FREQUENCY - MIN_FREQUENCY))

            # Send the values to the corresponding OSC addresses
            client.send_message("/eeg/alpha_amplitude", alpha_amplitude)
            client.send_message("/eeg/alpha_frequency", alpha_frequency)

            # Print a message for debugging
            print(f"Sent Alpha Amplitude: {alpha_amplitude:.2f}, Frequency: {alpha_frequency:.2f} Hz")

            # Wait for a short interval
            time.sleep(0.1)
            time_elapsed += 0.1

        except KeyboardInterrupt:
            print("\nStreaming stopped.")
            break

if __name__ == "__main__":
    main()