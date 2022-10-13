# Tiny Overlapping Trie

This is an experiment in building a tiny trie structure.
It's not very useful.

Inspired by ["A Hash Table Without Hash Functions"](https://arxiv.org/abs/2209.06038) this trie uses a _single_ backing array for storing the children of across _all_ nodes.
The idea being that many of children will actually be _null_, so allocating separate arrays for every single node is very wasteful.
The backing array is _rotated_ in the sense that different nodes will map their children to different offsets of the array.
This helps randomizing the use of the array even if the symbols used aren't uniformly distributed.

Whenever traversing this trie we need to know whether the next node is actually _our_ children or the children of another node.
We solve this by assigning each node a unique _id_, and that each node has a reference to its _parent id_.

There will of course still be a lot of collisions so to alleviate this we treat the backing array as a Cuckoo hash table:
We will actually have _two_ possible locations to place children and for each location we store _four values_ in total.
Inspired by ["Fast Concurrent Cuckoo Kick-Out Eviction Schemes for High-Density Tables"](https://arxiv.org/abs/1605.05236) we use a simple scheme of ghost-insertions.
In practice, on a subset of `/usr/share/dict/words`, we're able to have a load factor of ~88%.
A simple benchmark suggests that this is twice as slow as Zig's built-in HashMap implementation.

This trie is completely not expandable at all:
We have a fixed array of 256 locations (each capable of storing 4 nodes each).
With a load factor of 85% this means we can store ~870 nodes which turn out to be only a few hundreds keys.
On the positive note, we are quite efficiently storing this:
Each node only takes 32 bits.

There might be a way to use this as a building block for a trie which can grow and handle more keys.
For now it's only been a fun experiment.

["Cuckoo Trie: Exploiting Memory-Level Parallelism for Efficient DRAM Indexing"](https://arxiv.org/abs/2201.09331) shares some similarities (notably in the way of using Cuckoo hashing) and might be a more interesting direction to investigate further.
