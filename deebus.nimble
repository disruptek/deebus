version = "1.0.3"
author = "disruptek"
description = "some sugar for dbus"
license = "MIT"
requires "nim >= 1.0.0"
requires "https://github.com/zielmicha/nim-dbus#6c1dde5a37c880a9357f795d1ba0e69f3c0ba63f"

proc execCmd(cmd: string) =
  echo "execCmd:" & cmd
  exec cmd

proc execTest(test: string) =
  execCmd "nim c           -f -r " & test
  execCmd "nim c   -d:release -r " & test
  execCmd "nim c   -d:danger  -r " & test
  execCmd "nim cpp            -r " & test
  execCmd "nim cpp -d:danger  -r " & test
  when NimMajor >= 1 and NimMinor >= 1:
    execCmd "nim c --useVersion:1.0 -d:danger -r " & test
    execCmd "nim c   --gc:arc --exceptions:goto -r " & test
    execCmd "nim cpp --gc:arc --exceptions:goto -r " & test

task test, "run tests for travis":
  execTest("deebus.nim")
