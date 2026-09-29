using System;
using System.Collections.Generic;

namespace Thornswood
{
    /// <summary>
    /// "Is any of it still running?", asked cheaply while the game runs.
    ///
    /// Issue #978, from the #963 audit: the launcher's two second tick asked
    /// Checks.GameRunning, which listed every process on the machine four
    /// times over (once per name it looks for) and read the path of each
    /// match, every two seconds for the whole session.
    ///
    /// This keeps what the last full look found and asks only those, by the
    /// handle each already has, whether they have exited. While any of them is
    /// up the answer is yes and nothing is listed. Only when all of them have
    /// gone (or one cannot be asked) does it look again, and that look is the
    /// same one GameRunning makes, so a helper the game left behind is still
    /// found on the tick the game closes. The answer is the same as
    /// GameRunning's, tick for tick: a process that matched keeps matching for
    /// as long as it lives, because its name and folder do not change.
    ///
    /// No thread of its own; the caller's tick drives it. Not thread safe,
    /// and it does not need to be: one tick, one thread.
    /// </summary>
    class Watched<T> where T : class
    {
        readonly Func<List<T>> look;
        readonly Func<T, bool> up;
        readonly Action<T> drop;
        List<T> seen = new List<T>();

        /// <summary>How many full looks it has made, for the test.</summary>
        public int Looks;

        /// <param name="look">The full look: everything that counts, now.</param>
        /// <param name="up">True only when this one is provably still running.</param>
        /// <param name="drop">Lets go of one the watch no longer keeps.</param>
        public Watched(Func<List<T>> look, Func<T, bool> up, Action<T> drop)
        {
            this.look = look;
            this.up = up;
            this.drop = drop;
        }

        public bool Any()
        {
            foreach (T p in seen)
            {
                if (up(p)) return true;
            }
            Forget();
            List<T> now = look();
            Looks++;
            seen = now ?? new List<T>();
            return seen.Count > 0;
        }

        /// <summary>Lets go of everything kept. The next Any looks again.</summary>
        public void Forget()
        {
            foreach (T p in seen) drop(p);
            seen = new List<T>();
        }
    }
}
