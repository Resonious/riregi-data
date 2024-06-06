# riregi-data

Data layer for [Riregi](https://github.com/Resonious/riregi).

The idea is that we just mmap the entire application state and let the OS handle paging and writing back to disk. Yes, I know this is insane. But hey, the app cold starts almost instantly so I think it's pretty cool (although I do realize that the app is small enough for that to be true regardless of how I store data...).
