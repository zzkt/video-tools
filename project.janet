(declare-project
  :name "video-tools"
  :description "Video tools: scene splitting, colour grading, etc."
  :author "nik gaffney <nik@fo.am>"
  :url "https://codeberg.org/zzkt/video-tools"
  :license "GPL-3.0-or-later"
  :version "1.1.0"
  :dependencies [
    {:url "https://github.com/ianthehenry/cmd.git"
     :tag "v1.1.0"}
  ])

(declare-executable
  :name "scenesplit"
  :entry "scenesplit.janet")

(declare-executable
  :name "colourgrade"
  :entry "colourgrade.janet")

(declare-executable
  :name "colourstrip"
  :entry "colourstrip.janet")

(declare-executable
  :name "slitscan"
  :entry "slitscan.janet")
