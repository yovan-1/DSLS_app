#!/usr/bin/env python3
import wave
import struct
import math
import os

def generate_tone(filename, frequency, duration_ms, sample_rate=44100):
    """Generate a simple beep tone WAV file."""
    num_samples = int(sample_rate * duration_ms / 1000)
    
    with wave.open(filename, 'w') as wav_file:
        wav_file.setnchannels(1)
        wav_file.setsampwidth(2)
        wav_file.setframerate(sample_rate)
        
        for i in range(num_samples):
            t = i / sample_rate
            amplitude = 16000
            value = amplitude * math.sin(2 * math.pi * frequency * t)
            data = struct.pack('<h', int(value))
            wav_file.writeframesraw(data)

def generate_warning_alert():
    """Generate warning alert - two ascending beeps."""
    sample_rate = 44100
    duration_ms = 400
    num_samples = int(sample_rate * duration_ms / 1000)
    
    with wave.open('warning_alert.wav', 'w') as wav_file:
        wav_file.setnchannels(1)
        wav_file.setsampwidth(2)
        wav_file.setframerate(sample_rate)
        
        for i in range(num_samples):
            t = i / sample_rate
            amplitude = 16000
            
            # Two beeps: 800Hz then 1000Hz
            if i < num_samples // 2:
                freq = 800
            else:
                freq = 1000
            
            value = amplitude * math.sin(2 * math.pi * freq * t)
            data = struct.pack('<h', int(value))
            wav_file.writeframesraw(data)

def generate_critical_alert():
    """Generate critical alert - three rapid beeps at higher frequency."""
    sample_rate = 44100
    duration_ms = 600
    num_samples = int(sample_rate * duration_ms / 1000)
    
    with wave.open('critical_alert.wav', 'w') as wav_file:
        wav_file.setnchannels(1)
        wav_file.setsampwidth(2)
        wav_file.setframerate(sample_rate)
        
        for i in range(num_samples):
            t = i / sample_rate
            amplitude = 20000
            
            # Three beeps at 1200Hz
            beep = i % (num_samples // 3)
            if beep < num_samples // 6:
                freq = 1200
            else:
                freq = 0
            
            value = amplitude * math.sin(2 * math.pi * freq * t)
            data = struct.pack('<h', int(value))
            wav_file.writeframesraw(data)

os.chdir('/home/david11/DSLS_app/assets/sounds')

print("Generating warning_alert.wav...")
generate_warning_alert()

print("Generating critical_alert.wav...")
generate_critical_alert()

print("Done! Files created:")
for f in os.listdir('.'):
    print(f"  - {f}")