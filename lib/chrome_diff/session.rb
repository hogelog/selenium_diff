require "ferrum"

require "fileutils"
require "tmpdir"
require "open3"
require "logger"

module ChromeDiff
  class CompareStatus
    attr_reader :status, :diff, :diff_percent

    def initialize(status, stderr, width, height, threshold)
      @status = status
      @threshold = threshold

      @diff = stderr.to_f.to_i
      @diff_percent = @diff.to_f / width / height * 100
    end

    def success?
      @diff_percent <= @threshold
    end
  end

  class Session
    attr_reader :browser

    def initialize(width: nil, height: nil, timeout: nil, debug: false)
      @width = width || ChromeDiff::DEFAULT_OPTIONS[:width]
      @height = height || ChromeDiff::DEFAULT_OPTIONS[:height]
      @timeout = timeout || ChromeDiff::DEFAULT_OPTIONS[:timeout]
      @debug = debug
      options = {
        window_size: [@width, @height],
        timeout: @timeout,
        browser_options: {
          "device-scale-factor" => 1,
          "force-device-scale-factor" => nil,
        },
      }
      if @debug
        options[:logger] = STDOUT
        options[:headless] = false
      end

      @browser = Ferrum::Browser.new(options)
      @browser.resize(width: @width, height: @height)
    end

    def compare(from_url:, to_url:, output:, threshold: nil, full_screenshot: nil)
      threshold ||= ChromeDiff::DEFAULT_OPTIONS[:threshold]
      result = nil
      Dir.mktmpdir do |tmpdir|
        from_file = File.join(tmpdir, "from.png")
        to_file = File.join(tmpdir, "to.png")
        diff_file = File.join(tmpdir, "diff.png")

        screenshot(from_url, from_file, full_screenshot)
        screenshot(to_url, to_file, full_screenshot)

        _stdout, stderr, status =  Open3.capture3("compare", "-metric", "AE", from_file, to_file, diff_file)
        result = CompareStatus.new(status, stderr, @width, @height, threshold)

        File.rename(diff_file, output) if output
      end

      result
    end

    def screenshot(url, file, full)
      @browser.goto(url)
      wait_complete
      @browser.resize(width: @width, height: @height)
      @browser.screenshot(path: file, full: full)
    end

    def wait_complete
      @browser.network.wait_for_idle
      Timeout.timeout(@timeout) do
        until @browser.page.evaluate('document.readyState') == "complete"
          sleep 0.1
        end
      end
    end
  end
end
