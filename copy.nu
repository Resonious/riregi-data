#!/usr/bin/nu

mkdir ../riregi/android/app/src/main/jnilibs

ls zig-out/lib |
   where type == dir |
   each { |x| cp -r $x.name ../riregi/android/app/src/main/jnilibs }

ls ../riregi/android/app/src/main/jnilibs | get name | each { |x| ls $x } | flatten
