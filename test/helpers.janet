
# test helpers

(def video-dir (string (os/cwd) "/test/video"))
(def image-dir (string (os/cwd) "/test/images"))
(def output-dir (string (os/cwd) "/test/output"))

(defn ensure-dir [dir]
  (unless (= (os/stat dir :mode) :directory)
    (os/mkdir dir)))

(defn shell [& args]
  (os/execute args :p))

(defn file-exists? [path]
  (not= nil (os/stat path)))

(defn get-duration [video]
  (def raw (string/trim (slurp (string "/tmp/test_dur_" (math/random)))))
  (shell "sh" "-c" (string "ffprobe -v error -show_entries format=duration -of csv=p=0 " video " > /tmp/test_dur " (math/random) " 2>&1"))
  (def result (try (scan-number (string/trim (slurp "/tmp/test_dur"))) ([_] 0)))
  (os/rm "/tmp/test_dur")
  result)
