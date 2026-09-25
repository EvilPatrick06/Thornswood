using System;
using System.Collections.Generic;

namespace Thornswood
{
    // Where a character sits in the menu's list, and the one rule that moves
    // it.
    //
    // The menu draws slot n as the character the launcher numbered n, and the
    // numbers are fixed: forgetting the one in slot 2 leaves slot 2 empty
    // between 1 and 3 rather than sliding 3 down into it. Patrick, 20
    // September: "when I deleted a character the slots moved, I want each slot
    // to stay as is and so slot 1 and 3 could have things in them and slot 2
    // says make a new character".
    //
    // A number can still sit above the allowance: an account that had three
    // slots and drops to two, or a list written before NextSlot handed out the
    // lowest free number, when the numbers climbed to 3, 4, 5 on a three slot
    // account. The menu draws such a character after the fixed slots, so
    // nobody loses one. But while a number at or below the allowance is free
    // the character takes it, lowest number first, so the order they were
    // made in is the order they come in.
    //
    // Pure, and it refers to nothing else in the launcher, so a harness can
    // compile it alone with a test.
    static class Slots
    {
        /// <summary>
        /// The new number for each of the given ones, in the same order. A
        /// number at or below the allowance never changes. A number above it
        /// takes the lowest free number at or below the allowance while there
        /// is one, lowest number first; the rest keep theirs. Zero and below
        /// are not slots (the spare lives on 0) and come back as they were,
        /// holding nothing.
        /// </summary>
        public static int[] Tidy(int[] slots, int allowance)
        {
            var next = new int[slots.Length];
            var taken = new List<int>();
            for (int i = 0; i < slots.Length; i++)
            {
                next[i] = slots[i];
                if (slots[i] >= 1 && slots[i] <= allowance && !taken.Contains(slots[i])) taken.Add(slots[i]);
            }

            // The ones above the allowance, lowest first. Two rows on one
            // number keep their file order between themselves.
            var above = new List<int>();
            for (int i = 0; i < slots.Length; i++) if (slots[i] > allowance && slots[i] > 0) above.Add(i);
            above.Sort(delegate (int a, int b)
            {
                int c = slots[a].CompareTo(slots[b]);
                return c != 0 ? c : a.CompareTo(b);
            });

            foreach (int i in above)
            {
                int free = 1;
                while (free <= allowance && taken.Contains(free)) free++;
                if (free > allowance) break;
                next[i] = free;
                taken.Add(free);
            }
            return next;
        }
    }
}
