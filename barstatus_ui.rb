#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'io/console'
require 'fileutils'

CONFIG_PATH = File.expand_path('~/.claude/utils/claude_monitor_statusline/barstatus.config.json')

DEFAULT_CONFIG = {
  'version' => 1,
  'display_mode' => 'compact',
  'bar_style' => 'blocks',
  'show_5h' => true,
  'show_7d' => true,
  'show_ctx' => true,
  'show_git' => true,
  'show_duration' => true
}.freeze

ITEMS = [
  { key: 'display_mode', label: 'Display Mode', type: :enum, options: %w[compact full minimal], desc: 'Layout density' },
  { key: 'bar_style', label: 'Bar Style', type: :enum, options: %w[blocks tqdm percent_only], desc: 'Progress bar rendering' },
  { key: 'show_5h', label: '5h Usage', type: :bool, desc: '5-hour rolling limit' },
  { key: 'show_7d', label: '7d Usage', type: :bool, desc: '7-day usage quota' },
  { key: 'show_ctx', label: 'Context', type: :bool, desc: 'Context window usage' },
  { key: 'show_git', label: 'Git Info', type: :bool, desc: 'Branch & status indicators' },
  { key: 'show_duration', label: 'Duration', type: :bool, desc: 'Session elapsed time' }
].freeze

# ANSI color helpers
module C
  RESET   = "\e[0m"
  BOLD    = "\e[1m"
  DIM     = "\e[2m"
  ITALIC  = "\e[3m"
  UNDER   = "\e[4m"

  BLACK   = "\e[30m"
  RED     = "\e[31m"
  GREEN   = "\e[32m"
  YELLOW  = "\e[33m"
  BLUE    = "\e[34m"
  MAGENTA = "\e[35m"
  CYAN    = "\e[36m"
  WHITE   = "\e[37m"

  BG_BLUE    = "\e[44m"
  BG_CYAN    = "\e[46m"
  BG_GREEN   = "\e[42m"
  BG_MAGENTA = "\e[45m"

  GRAY    = "\e[90m"
  BR_CYAN = "\e[96m"
  BR_GREEN = "\e[92m"
  BR_YELLOW = "\e[93m"
  BR_MAGENTA = "\e[95m"
  BR_WHITE = "\e[97m"
end

# Box drawing
module Box
  TL = "\u250C" # top-left
  TR = "\u2510" # top-right
  BL = "\u2514" # bottom-left
  BR = "\u2518" # bottom-right
  H  = "\u2500" # horizontal
  V  = "\u2502" # vertical
  LT = "\u251C" # left-tee
  RT = "\u2524" # right-tee
end

class BarstatusMenu
  WIDTH = 56

  def initialize
    @selected_index = 0
    @dirty = false
    @warning = nil
    @config = load_config
  end

  def run
    loop do
      render
      key = read_key
      case key
      when :up
        @selected_index = (@selected_index - 1) % ITEMS.length
      when :down
        @selected_index = (@selected_index + 1) % ITEMS.length
      when :left
        apply_change(-1)
      when :right
        apply_change(1)
      when :enter
        save_config
        render_saved_message
        return 0
      when :cancel
        render_cancel_message
        return 0
      when :ctrl_c
        print "\e[?25h" # restore cursor
        puts ""
        return 130
      end
    end
  ensure
    print "\e[?25h" # restore cursor
    system('stty sane >/dev/null 2>&1')
  end

  private

  def load_config
    return DEFAULT_CONFIG.dup unless File.exist?(CONFIG_PATH)

    parsed = JSON.parse(File.read(CONFIG_PATH))
    sanitize_config(parsed)
  rescue JSON::ParserError
    @warning = "Invalid config file — using defaults"
    DEFAULT_CONFIG.dup
  rescue StandardError => e
    @warning = "Cannot read config (#{e.class}) — using defaults"
    DEFAULT_CONFIG.dup
  end

  def sanitize_config(raw)
    cfg = DEFAULT_CONFIG.dup
    cfg['display_mode'] = raw['display_mode'] if %w[compact full minimal].include?(raw['display_mode'])
    cfg['bar_style'] = raw['bar_style'] if %w[tqdm blocks percent_only].include?(raw['bar_style'])
    %w[show_5h show_7d show_ctx show_git show_duration].each do |flag|
      cfg[flag] = !!raw[flag] unless raw[flag].nil?
    end
    cfg
  end

  def save_config
    @config['version'] = 1
    FileUtils.mkdir_p(File.dirname(CONFIG_PATH))
    tmp_path = "#{CONFIG_PATH}.tmp"
    File.write(tmp_path, "#{JSON.pretty_generate(@config)}\n")
    File.rename(tmp_path, CONFIG_PATH)
    @dirty = false
  end

  def render
    print "\e[?25l" # hide cursor
    print "\e[H\e[2J" # clear screen

    render_header
    render_separator
    render_keybinds
    render_separator
    render_status_bar
    render_separator
    render_items
    render_separator
    render_preview
    render_footer
  end

  def render_header
    title = " bar-status "
    pad = WIDTH - 2 - title.length
    left_pad = pad / 2
    right_pad = pad - left_pad

    puts "#{C::CYAN}#{Box::TL}#{Box::H * left_pad}#{C::BOLD}#{C::BR_CYAN}#{title}#{C::RESET}#{C::CYAN}#{Box::H * right_pad}#{Box::TR}#{C::RESET}"
    puts "#{C::CYAN}#{Box::V}#{C::RESET}#{C::DIM}  Claude Code Statusline Configurator#{' ' * (WIDTH - 40)}#{C::RESET}#{C::CYAN}#{Box::V}#{C::RESET}"
  end

  def render_separator
    puts "#{C::CYAN}#{Box::LT}#{Box::H * (WIDTH - 2)}#{Box::RT}#{C::RESET}"
  end

  def render_keybinds
    line1 = "  #{C::DIM}#{C::CYAN}\u2191\u2193#{C::RESET}#{C::DIM} select   #{C::CYAN}\u2190\u2192#{C::RESET}#{C::DIM} modify   #{C::GREEN}Enter#{C::RESET}#{C::DIM} save   #{C::RED}q#{C::RESET}#{C::DIM} quit#{C::RESET}"
    puts "#{C::CYAN}#{Box::V}#{C::RESET}#{line1}#{visible_padding(line1, WIDTH - 2)}#{C::CYAN}#{Box::V}#{C::RESET}"
  end

  def render_status_bar
    state = @dirty ? "#{C::BR_YELLOW}\u25CF modified" : "#{C::BR_GREEN}\u25CF saved"
    warn_part = @warning ? "  #{C::RED}#{@warning}" : ""
    line = "  #{state}#{C::RESET}#{warn_part}"
    puts "#{C::CYAN}#{Box::V}#{C::RESET}#{line}#{visible_padding(line, WIDTH - 2)}#{C::CYAN}#{Box::V}#{C::RESET}"
  end

  def render_items
    ITEMS.each_with_index do |item, idx|
      selected = idx == @selected_index
      value = display_value(item)

      if selected
        pointer = "#{C::BR_CYAN}\u25B6#{C::RESET}"
        label = "#{C::BOLD}#{C::BR_WHITE}#{item[:label]}#{C::RESET}"
        val_str = format_value_colored(item, value, true)
        desc = "#{C::DIM}#{item[:desc]}#{C::RESET}"
        line = "  #{pointer} #{label.ljust(28)}#{val_str}"
        puts "#{C::CYAN}#{Box::V}#{C::RESET}#{line}#{visible_padding(line, WIDTH - 2)}#{C::CYAN}#{Box::V}#{C::RESET}"
        desc_line = "      #{desc}"
        puts "#{C::CYAN}#{Box::V}#{C::RESET}#{desc_line}#{visible_padding(desc_line, WIDTH - 2)}#{C::CYAN}#{Box::V}#{C::RESET}"
      else
        pointer = " "
        label = "#{C::WHITE}#{item[:label]}#{C::RESET}"
        val_str = format_value_colored(item, value, false)
        line = "  #{pointer} #{label.ljust(28)}#{val_str}"
        puts "#{C::CYAN}#{Box::V}#{C::RESET}#{line}#{visible_padding(line, WIDTH - 2)}#{C::CYAN}#{Box::V}#{C::RESET}"
      end
    end
  end

  def render_preview
    parts = []
    parts << "#{C::CYAN}proj/#{C::RESET}"
    parts << "#{C::GREEN}main#{C::RESET}" if @config['show_git']
    parts << "#{C::MAGENTA}Opus#{C::RESET}"
    parts << "#{C::DIM}12m#{C::RESET}" if @config['show_duration']

    if @config['show_ctx']
      bar = preview_bar(42)
      parts << "#{C::DIM}ctx #{bar} 42%#{C::RESET}"
    end

    if @config['show_5h']
      bar = preview_bar(67)
      parts << "#{C::DIM}5h #{bar} #{C::YELLOW}67%#{C::RESET}"
    end

    if @config['show_7d']
      bar = preview_bar(23)
      parts << "#{C::DIM}7d #{bar} #{C::GREEN}23%#{C::RESET}"
    end

    preview_text = parts.join(" #{C::DIM}\u00B7#{C::RESET} ")
    label_line = "  #{C::DIM}Preview:#{C::RESET}"
    puts "#{C::CYAN}#{Box::V}#{C::RESET}#{label_line}#{visible_padding(label_line, WIDTH - 2)}#{C::CYAN}#{Box::V}#{C::RESET}"
    preview_line = "  #{preview_text}"
    puts "#{C::CYAN}#{Box::V}#{C::RESET}#{preview_line}#{visible_padding(preview_line, WIDTH - 2)}#{C::CYAN}#{Box::V}#{C::RESET}"
  end

  def preview_bar(pct)
    case @config['bar_style']
    when 'blocks'
      filled = (pct / 10.0).round
      empty = 10 - filled
      color = pct >= 75 ? C::RED : pct >= 50 ? C::YELLOW : C::GREEN
      "#{C::DIM}[#{color}#{'█' * filled}#{C::DIM}#{'░' * empty}]#{C::RESET}"
    when 'tqdm'
      filled = (pct / 10.0).round
      empty = 10 - filled
      color = pct >= 75 ? C::RED : pct >= 50 ? C::YELLOW : C::GREEN
      "#{C::DIM}[#{color}#{'#' * filled}#{C::DIM}#{'-' * empty}]#{C::RESET}"
    when 'percent_only'
      color = pct >= 75 ? C::RED : pct >= 50 ? C::YELLOW : C::GREEN
      "#{color}#{pct}%#{C::RESET}"
    end
  end

  def render_footer
    path_line = "  #{C::DIM}#{CONFIG_PATH}#{C::RESET}"
    puts "#{C::CYAN}#{Box::V}#{C::RESET}#{path_line}#{visible_padding(path_line, WIDTH - 2)}#{C::CYAN}#{Box::V}#{C::RESET}"
    puts "#{C::CYAN}#{Box::BL}#{Box::H * (WIDTH - 2)}#{Box::BR}#{C::RESET}"
  end

  def render_saved_message
    print "\e[H\e[2J"
    puts ""
    puts "  #{C::BR_GREEN}#{C::BOLD}\u2713 Configuration saved#{C::RESET}"
    puts "  #{C::DIM}Changes will appear on the next statusline refresh.#{C::RESET}"
    puts "  #{C::DIM}#{CONFIG_PATH}#{C::RESET}"
    puts ""
  end

  def render_cancel_message
    print "\e[H\e[2J"
    puts ""
    puts "  #{C::YELLOW}Cancelled#{C::RESET} #{C::DIM}— no changes saved.#{C::RESET}"
    puts ""
  end

  def display_value(item)
    value = @config[item[:key]]
    if item[:type] == :bool
      value ? 'on' : 'off'
    else
      value.to_s
    end
  end

  def format_value_colored(item, value, selected)
    if item[:type] == :bool
      if value == 'on'
        selected ? "#{C::BR_GREEN}#{C::BOLD}\u25C9 on#{C::RESET}" : "#{C::GREEN}\u25C9 on#{C::RESET}"
      else
        selected ? "#{C::RED}#{C::BOLD}\u25CB off#{C::RESET}" : "#{C::DIM}\u25CB off#{C::RESET}"
      end
    else
      if selected
        options = item[:options]
        current_idx = options.index(@config[item[:key]]) || 0
        options.each_with_index.map do |opt, i|
          if i == current_idx
            "#{C::BR_CYAN}#{C::BOLD}#{C::UNDER}#{opt}#{C::RESET}"
          else
            "#{C::DIM}#{opt}#{C::RESET}"
          end
        end.join("#{C::DIM} | #{C::RESET}")
      else
        "#{C::WHITE}#{value}#{C::RESET}"
      end
    end
  end

  def apply_change(direction)
    item = ITEMS[@selected_index]
    key = item[:key]
    old = @config[key]

    if item[:type] == :bool
      @config[key] = !@config[key]
    else
      options = item[:options]
      current_index = options.index(@config[key]) || 0
      next_index = (current_index + direction) % options.length
      @config[key] = options[next_index]
    end

    @dirty = true if old != @config[key]
  end

  # Calculate visible string length (strip ANSI codes)
  def visible_length(str)
    str.gsub(/\e\[[0-9;]*m/, '').length
  end

  def visible_padding(str, target_width)
    visible = visible_length(str)
    remaining = target_width - visible
    remaining > 0 ? ' ' * remaining : ''
  end

  def read_key
    char = STDIN.getch
    return :ctrl_c if char == "\u0003"
    return :cancel if %w[q Q].include?(char)
    return :up if %w[k K].include?(char)
    return :down if %w[j J].include?(char)
    return :left if %w[h H].include?(char)
    return :right if %w[l L].include?(char)
    return :enter if ["\r", "\n"].include?(char)

    return nil unless char == "\e"

    second = STDIN.read_nonblock(1, exception: false)
    return :cancel if second.nil?
    return :cancel unless second == '['

    third = STDIN.read_nonblock(1, exception: false)
    case third
    when 'A' then :up
    when 'B' then :down
    when 'C' then :right
    when 'D' then :left
    else nil
    end
  rescue StandardError
    nil
  end
end

exit(BarstatusMenu.new.run)
