using System;
using System.Collections.Generic;

namespace Thornswood
{
    /// <summary>
    /// Everybody this person can hear, mixed into one stereo stream for the
    /// speakers: what the voice page's Web Audio graph did, a PannerNode
    /// and a GainNode per person into the AudioContext's destination.
    ///
    /// The numbers are the page's. The distance model is the PannerNode's
    /// 'inverse' with refDistance 1 and rolloffFactor 0, which is 1 at every
    /// distance: the panner only places the voice, and how loud it is comes
    /// from the speaker's mode (levelFor in VoiceSession.cs). The level moves
    /// the way the page's setTargetAtTime(value, now, 0.05) moved it, an
    /// exponential approach with a 50 ms time constant, so a position a fifth
    /// of a second later does not click.
    ///
    /// One thing is not the page's. Its panner was 'HRTF', which filters each
    /// voice through a set of measured head related impulse responses that
    /// ship inside Chromium. This launcher has no such set and no right to
    /// copy Chromium's, so the panner here is Web Audio's other model,
    /// 'equalpower', exactly as the Web Audio specification gives it: left
    /// and right gains from the voice's azimuth. Left and right are where
    /// they were; above, below and behind are no longer heard as different.
    ///
    /// Each person has a little buffer in front of the mix (jitter), because
    /// packets arrive in bursts and the speakers take samples evenly. It
    /// starts playing at 40 ms, plays out when it runs dry, and drops its
    /// oldest audio when more than 200 ms pile up, so a burst never becomes
    /// lasting delay.
    /// </summary>
    sealed class VoiceMix
    {
        public const int Rate = 48000;
        public const int Frame = 960;   // 20 ms

        const int Prime = Rate * 40 / 1000;
        const int Most = Rate * 200 / 1000;
        const int Keep = Rate * 60 / 1000;

        // setTargetAtTime's time constant, 0.05 s, as a per sample step.
        static readonly float Approach = (float)(1 - Math.Exp(-1.0 / (0.05 * Rate)));

        // The PannerNode's distance settings, as the page set them.
        const double RefDistance = 1;
        const double RolloffFactor = 0;

        sealed class Source
        {
            public readonly float[] Ring = new float[Rate];
            public int Read, Count;
            public bool Primed;
            public bool Audible = true;
            public float Gain = 1, GainTarget = 1;
            public float Left = (float)Math.Cos(Math.PI / 4), Right = (float)Math.Sin(Math.PI / 4);
            public float LeftTarget = (float)Math.Cos(Math.PI / 4), RightTarget = (float)Math.Sin(Math.PI / 4);
        }

        readonly object gate = new object();
        readonly Dictionary<int, Source> sources = new Dictionary<int, Source>();

        Source At(int id)
        {
            Source s;
            if (!sources.TryGetValue(id, out s)) { s = new Source(); sources[id] = s; }
            return s;
        }

        /// <summary>
        /// Starts a person silent, as the page started a gain node at 0 for
        /// somebody already muted, so nothing is heard before the first
        /// position says how loud they are.
        /// </summary>
        public void Add(int id, bool silent)
        {
            lock (gate)
            {
                Source s = At(id);
                if (silent) { s.Gain = 0; s.GainTarget = 0; }
            }
        }

        public void Remove(int id)
        {
            lock (gate) sources.Remove(id);
        }

        /// <summary>Decoded audio from one person, mono at 48 kHz.</summary>
        public void Push(int id, ReadOnlySpan<float> pcm)
        {
            lock (gate)
            {
                Source s;
                if (!sources.TryGetValue(id, out s) || !s.Audible) return;
                int n = Math.Min(pcm.Length, s.Ring.Length);
                for (int i = 0; i < n; i++)
                {
                    s.Ring[(s.Read + s.Count) % s.Ring.Length] = pcm[i];
                    if (s.Count < s.Ring.Length) s.Count++;
                    else s.Read = (s.Read + 1) % s.Ring.Length;
                }
                if (s.Count > Most)
                {
                    int drop = s.Count - Keep;
                    s.Read = (s.Read + drop) % s.Ring.Length;
                    s.Count -= drop;
                }
            }
        }

        /// <summary>The gain node's value, approached as setTargetAtTime approached it.</summary>
        public void SetLevel(int id, double level)
        {
            lock (gate)
            {
                Source s;
                if (sources.TryGetValue(id, out s)) s.GainTarget = (float)level;
            }
        }

        /// <summary>
        /// Whether this person's audio is taken at all: the page's hear(),
        /// which turned their incoming track off for a mute or a staff
        /// silence, so nothing of theirs played whatever the gain said.
        /// </summary>
        public void SetAudible(int id, bool on)
        {
            lock (gate)
            {
                Source s;
                if (!sources.TryGetValue(id, out s)) return;
                s.Audible = on;
                if (!on) { s.Count = 0; s.Primed = false; }
            }
        }

        /// <summary>
        /// Where the voice is, in the listener's frame as the page gave it to
        /// the PannerNode: x to the right, y up, z behind (so what is in
        /// front is negative z). The listener is Web Audio's default, at the
        /// origin facing -z with +y up.
        /// </summary>
        public void SetPosition(int id, double x, double y, double z)
        {
            double l, r;
            EqualPower(x, y, z, out l, out r);
            double d = DistanceGain(Math.Sqrt(x * x + y * y + z * z));
            lock (gate)
            {
                Source s;
                if (!sources.TryGetValue(id, out s)) return;
                s.LeftTarget = (float)(l * d);
                s.RightTarget = (float)(r * d);
            }
        }

        /// <summary>
        /// The PannerNode's 'inverse' distance model:
        /// ref / (ref + rolloff * (max(d, ref) - ref)). With the page's
        /// rolloffFactor of 0 it is 1 wherever the voice is.
        /// </summary>
        public static double DistanceGain(double distance)
        {
            double d = Math.Max(distance, RefDistance);
            return RefDistance / (RefDistance + RolloffFactor * (d - RefDistance));
        }

        /// <summary>
        /// Web Audio's equal-power panning of a mono input (the
        /// specification's azimuth and elevation, then its equal-power
        /// algorithm), for the default listener.
        /// </summary>
        public static void EqualPower(double x, double y, double z, out double left, out double right)
        {
            double azimuth = 0;
            double len = Math.Sqrt(x * x + y * y + z * z);
            if (len > 0)
            {
                // Listener: forward (0,0,-1), up (0,1,0), right = forward x up = (1,0,0).
                double sx = x / len, sy = y / len, sz = z / len;
                // Project onto the listener's horizontal plane.
                double px = sx, pz = sz;
                double plen = Math.Sqrt(px * px + pz * pz);
                if (plen > 0)
                {
                    px /= plen; pz /= plen;
                    azimuth = 180 * Math.Acos(Math.Max(-1, Math.Min(1, px))) / Math.PI;
                    double frontBack = -pz;   // projected . forward
                    if (frontBack < 0) azimuth = 360 - azimuth;
                    if (azimuth >= 0 && azimuth <= 270) azimuth = 90 - azimuth;
                    else azimuth = 450 - azimuth;
                }
            }
            azimuth = Math.Max(-180, Math.Min(180, azimuth));
            if (azimuth < -90) azimuth = -180 - azimuth;
            else if (azimuth > 90) azimuth = 180 - azimuth;
            double xn = (azimuth + 90) / 180;
            left = Math.Cos(xn * Math.PI / 2);
            right = Math.Sin(xn * Math.PI / 2);
        }

        /// <summary>
        /// The next frames for the speakers, interleaved left and right,
        /// everybody summed and held inside -1 to 1.
        /// </summary>
        public void Render(Span<float> stereo, int frames)
        {
            stereo.Slice(0, frames * 2).Clear();
            lock (gate)
            {
                foreach (Source s in sources.Values)
                {
                    if (!s.Primed)
                    {
                        if (s.Count < Prime) continue;
                        s.Primed = true;
                    }
                    for (int i = 0; i < frames; i++)
                    {
                        s.Gain += (s.GainTarget - s.Gain) * Approach;
                        s.Left += (s.LeftTarget - s.Left) * Approach;
                        s.Right += (s.RightTarget - s.Right) * Approach;
                        if (s.Count == 0) { s.Primed = false; continue; }
                        float v = s.Ring[s.Read] * s.Gain;
                        s.Read = (s.Read + 1) % s.Ring.Length;
                        s.Count--;
                        stereo[2 * i] += v * s.Left;
                        stereo[2 * i + 1] += v * s.Right;
                    }
                }
            }
            for (int i = 0; i < frames * 2; i++)
            {
                float v = stereo[i];
                stereo[i] = v > 1 ? 1 : v < -1 ? -1 : v;
            }
        }
    }
}
