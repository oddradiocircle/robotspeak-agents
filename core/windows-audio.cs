// Per-stream Windows output routing. Does not change the system default device.
using System;
using System.IO;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Threading;

public static class RobotSpeakAudio {
    public class Device {
        public string id;
        public string name;
        public uint index;
    }
    [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
    struct Caps {
        public ushort Manufacturer, Product;
        public uint Version;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst=32)] public string Name;
        public uint Formats;
        public ushort Channels, Reserved;
        public uint Support;
    }
    [StructLayout(LayoutKind.Sequential, Pack=2)]
    struct Format {
        public ushort Tag, Channels;
        public uint Rate, BytesPerSecond;
        public ushort BlockAlign, Bits, ExtraSize;
    }
    [StructLayout(LayoutKind.Sequential)]
    struct Header {
        public IntPtr Data;
        public uint Length, Recorded;
        public UIntPtr User;
        public uint Flags, Loops;
        public IntPtr Next;
        public UIntPtr Reserved;
    }
    [DllImport("winmm.dll")] static extern uint waveOutGetNumDevs();
    [DllImport("winmm.dll", CharSet=CharSet.Unicode)] static extern uint waveOutGetDevCapsW(UIntPtr id, out Caps caps, uint size);
    [DllImport("winmm.dll")] static extern uint waveOutMessage(IntPtr id, uint message, IntPtr data, UIntPtr size);
    [DllImport("winmm.dll")] static extern uint waveOutOpen(out IntPtr handle, uint id, ref Format format, IntPtr callback, IntPtr instance, uint flags);
    [DllImport("winmm.dll")] static extern uint waveOutPrepareHeader(IntPtr handle, IntPtr header, uint size);
    [DllImport("winmm.dll")] static extern uint waveOutWrite(IntPtr handle, IntPtr header, uint size);
    [DllImport("winmm.dll")] static extern uint waveOutReset(IntPtr handle);
    [DllImport("winmm.dll")] static extern uint waveOutUnprepareHeader(IntPtr handle, IntPtr header, uint size);
    [DllImport("winmm.dll")] static extern uint waveOutClose(IntPtr handle);
    static void Check(uint result, string action) {
        if (result != 0) throw new IOException(action + " failed (WinMM " + result + ")");
    }
    public static Device[] List() {
        var devices = new System.Collections.Generic.List<Device>();
        for (uint i=0; i<waveOutGetNumDevs(); i++) {
            Caps caps;
            Check(waveOutGetDevCapsW(new UIntPtr(i), out caps, (uint)Marshal.SizeOf(typeof(Caps))), "Query device");
            IntPtr size = Marshal.AllocHGlobal(IntPtr.Size);
            IntPtr buffer = IntPtr.Zero;
            try {
                Marshal.WriteIntPtr(size, IntPtr.Zero);
                // DRV_QUERYFUNCTIONINSTANCEIDSIZE / DRV_QUERYFUNCTIONINSTANCEID.
                Check(waveOutMessage(new IntPtr(i), 0x0812, size, UIntPtr.Zero), "Query endpoint size");
                int bytes = Marshal.ReadInt32(size);
                if (bytes < 2 || bytes > 65536) throw new IOException("Invalid endpoint ID size");
                buffer = Marshal.AllocHGlobal(bytes);
                Check(waveOutMessage(new IntPtr(i), 0x0811, buffer, new UIntPtr((uint)bytes)), "Query endpoint ID");
                devices.Add(new Device { index=i, name=caps.Name, id=Marshal.PtrToStringUni(buffer) });
            } finally {
                if (buffer != IntPtr.Zero) Marshal.FreeHGlobal(buffer);
                Marshal.FreeHGlobal(size);
            }
        }
        return devices.ToArray();
    }
    public static byte[] ScalePcm(byte[] wav, int volume) {
        if (volume < 0 || volume > 100) throw new ArgumentOutOfRangeException("volume");
        // The bundled engines export this exact PCM layout, not arbitrary media.
        if (wav.Length < 44 || System.Text.Encoding.ASCII.GetString(wav,0,4)!="RIFF" ||
            System.Text.Encoding.ASCII.GetString(wav,8,8)!="WAVEfmt " ||
            BitConverter.ToUInt32(wav,16)!=16 || BitConverter.ToUInt16(wav,20)!=1 ||
            BitConverter.ToUInt16(wav,22)!=1 || BitConverter.ToUInt32(wav,24)!=22050 ||
            BitConverter.ToUInt16(wav,34)!=16 || System.Text.Encoding.ASCII.GetString(wav,36,4)!="data" ||
            BitConverter.ToUInt32(wav,40)!=(uint)(wav.Length-44) || (wav.Length-44)%2!=0) throw new IOException("Invalid RobotSpeak PCM file");
        if (volume != 100) {
            for (int i=44; i<wav.Length; i+=2) {
                short sample=(short)(BitConverter.ToInt16(wav,i) * volume / 100.0);
                wav[i]=(byte)(sample & 255);
                wav[i+1]=(byte)((sample >> 8) & 255);
            }
        }
        return wav;
    }
    public static void Play(string id, string path, int volume) {
        uint deviceIndex = UInt32.MaxValue; // WAVE_MAPPER follows the system default.
        if (id != "default") {
            Device selected = null;
            foreach (var device in List()) {
                if (String.Equals(device.id, id, StringComparison.OrdinalIgnoreCase)) { selected=device; break; }
            }
            if (selected == null) throw new IOException("Selected Windows audio device is unavailable: " + id);
            deviceIndex = selected.index;
        }
        byte[] wav = ScalePcm(File.ReadAllBytes(path), volume);
        var format = new Format { Tag=1, Channels=1, Rate=22050, BytesPerSecond=44100, BlockAlign=2, Bits=16 };
        IntPtr handle;
        Check(waveOutOpen(out handle, deviceIndex, ref format, IntPtr.Zero, IntPtr.Zero, 0), "Open audio device");
        GCHandle pinned = default(GCHandle);
        IntPtr memory = IntPtr.Zero;
        uint headerSize = (uint)Marshal.SizeOf(typeof(Header));
        bool prepared = false;
        try {
            pinned = GCHandle.Alloc(wav, GCHandleType.Pinned);
            var header = new Header { Data=IntPtr.Add(pinned.AddrOfPinnedObject(),44), Length=(uint)(wav.Length-44) };
            memory = Marshal.AllocHGlobal((int)headerSize);
            Marshal.StructureToPtr(header, memory, false);
            Check(waveOutPrepareHeader(handle,memory,headerSize), "Prepare audio");
            prepared = true;
            Check(waveOutWrite(handle,memory,headerSize), "Play audio");
            var watch = Stopwatch.StartNew();
            while ((((Header)Marshal.PtrToStructure(memory, typeof(Header))).Flags & 1) == 0) {
                if (watch.Elapsed.TotalSeconds > (wav.Length-44)/44100.0 + 5) throw new IOException("Audio playback timed out");
                Thread.Sleep(10);
            }
        } finally {
            waveOutReset(handle);
            if (prepared) waveOutUnprepareHeader(handle,memory,headerSize);
            waveOutClose(handle);
            if (memory != IntPtr.Zero) Marshal.FreeHGlobal(memory);
            if (pinned.IsAllocated) pinned.Free();
        }
    }
}
