using System;
using System.Collections.Concurrent;
using System.Threading;

namespace Thornswood
{
    /// <summary>
    /// The voice session's event loop: one job at a time, in the order they
    /// came, the way a browser ran voice-host.html before #4823. It is also
    /// the SynchronizationContext of the thread that runs the jobs, so an
    /// await in a job (a socket's handshake, its next message) comes back to
    /// the loop as a job of its own rather than going on in a pool thread
    /// beside it. Nothing the session holds is then touched from two threads
    /// at once.
    ///
    /// The launcher runs VoiceThread, below. tests\voice-launcher runs its
    /// own loop on the harness's thread, so it can tell when the session has
    /// nothing left to do.
    /// </summary>
    abstract class VoiceLoop : SynchronizationContext
    {
        /// <summary>Queues a job.</summary>
        public abstract void Add(Action job);

        /// <summary>Runs one last job and stops: nothing queued after it runs.</summary>
        public abstract void Finish(Action last);

        public override void Post(SendOrPostCallback d, object state) { Add(delegate { d(state); }); }

        public override void Send(SendOrPostCallback d, object state)
        {
            throw new NotSupportedException("the voice loop runs jobs in order and never waits on one");
        }

        public override SynchronizationContext CreateCopy() { return this; }

        /// <summary>One job, on this loop's thread, with this loop as its context.</summary>
        protected void RunOne(Action job)
        {
            SynchronizationContext was = Current;
            SetSynchronizationContext(this);
            try { job(); }
            catch (Exception ex) { Swallow.Note("VoiceSession, a job", ex); }
            finally { SetSynchronizationContext(was); }
        }
    }

    /// <summary>The launcher's voice loop: a background thread of its own.</summary>
    sealed class VoiceThread : VoiceLoop
    {
        readonly BlockingCollection<Action> jobs = new BlockingCollection<Action>();
        bool ended;   // read and written on the loop's thread only

        public VoiceThread()
        {
            new Thread(delegate () { foreach (Action job in jobs.GetConsumingEnumerable()) if (!ended) RunOne(job); })
            {
                IsBackground = true,
                Name = "Voice"
            }.Start();
        }

        public override void Add(Action job)
        {
            try { jobs.Add(job); }
            catch (InvalidOperationException ex) { Swallow.Note("VoiceThread.Add, after the end", ex); }
        }

        /// <summary>
        /// The last job, waited for up to two seconds: it closes the socket and
        /// the connections, which ask nothing of the network, so a loop that
        /// has not run it by then is stuck in a job and is left to the process.
        /// </summary>
        public override void Finish(Action last)
        {
            var done = new ManualResetEventSlim(false);
            Add(delegate { try { last(); } finally { ended = true; done.Set(); } });
            done.Wait(2000);
            jobs.CompleteAdding();
        }
    }
}
