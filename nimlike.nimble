# Package

version       = "1.0.0"
author        = "Eugene Medvedev"
description   = "A cgi-bin comments and likes system for Gemini"
license       = "MIT"
srcDir        = "src"
bin           = @["nimlike"]
binDir        = "build"

# Dependencies

requires "nim >= 1.6.4"
requires "jstin >= 0.1.0"
requires "elvis >= 0.5.0"
requires "regex >= 0.19.0"

# Tasks

# We're already requiring nim >= 1.4.8, so we can assume that 'distros' is available.
import os
import distros
from macros import error

# It's silly, but I have to reconstruct the compiler command line
# that nimble does in the build stage here to do multiple release builds.
# See https://github.com/nim-lang/nimble/issues/764
#
# This is kinda brittle.
#

task clean, "Clean the build directory.":
  rmDir(binDir)

task release, "Produce a static release build for supported platforms.":

  # External dependencies for Ubuntu required
  # to cross-compile release builds.

  if detectOs(Ubuntu):
    # ARM compiler
    foreignDep "gcc-arm-linux-gnueabihf"
  else:
    echo("Warning: Dependencies might be missing, you're on your own. ",
         "Check nimlike.nimble for details.")

    # I don't know the right invocations for foreignDep for anything
    # except Ubuntu, but at least I can tell if the executables
    # are there.
    for requiredExe in [
      "arm-linux-gnueabihf-gcc",
    ]:
       if findExe(requiredExe) == "":
         error(requiredExe & " binary was not found in PATH.")

  let
    compile = join(["c",
                    "-d:release",
                    "-d:strip",
                    "--opt:size",
                    "--passL:-static",
                    "-d:NimblePkgVersion=" & version]," ")
    linux_x64_exe = projectName() & "_amd64"
    linux_x64 = join(["--cpu:amd64",
                      "--os:linux",
                      "--out:build/" & linux_x64_exe]," ")

    raspberry_x32_exe = projectName() & "_armhf"
    raspberry_x32 = join(["--cpu:arm",
                          "--os:linux",
                          "--out:build/" & raspberry_x32_exe]," ")

    rootFile = os.joinpath(srcDir, projectName() & ".nim")

  cleanTask()

  echo "=== Building Linux amd64..."
  selfExec join([compile, linux_x64, rootFile], " ")

  echo "=== Building Raspberry x32..."
  echo join([compile, raspberry_x32, rootFile], " ")
  selfExec join([compile, raspberry_x32, rootFile], " ")

  echo "Done."
