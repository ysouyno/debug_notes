#!/bin/bash

OUT=$HOME/temp/libo_emf.log

export SAL_LOG_FILE=$OUT

if [ -f $OUT ]; then
    rm -f $OUT
    printf "delete: %s\n" $OUT
fi

export SAL_LOG=\
+INFO.vcl\
-INFO.vcl.schedule\
-INFO.vcl.unity\
-INFO.vcl.virdev\
+INFO.emfio\
-INFO.vcl.opengl\
+INFO.drawinglayer.emf\
+WARN.vcl.emf

$HOME/libo_build/instdir/program/simpress
