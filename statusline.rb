#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'date'
require 'set'

# DEBUG with
# echo '{"workspace": {"current_dir": "/Users/gdehan/.claude/utils/local-tts"}, "model": {"display_name": "Claude 4.1 Opus"}, "session_id": "test"}' | env CLAUDE_STATUS_DISPLAY_MODE=text CLAUDE_STATUS_PLAN=pro CLAUDE_STATUS_INFO_MODE=text ruby ./statusline.rb

# Claude Code Status Line - Clean, minimal, and precise
# Matches Claude Monitor's token calculation logic exactly
#
# Environment Variables:
#   CLAUDE_STATUS_DISPLAY_MODE - Display style: minimal, colors (default), or background
#   CLAUDE_STATUS_PLAN        - Plan type: pro, max5, max20, custom (defaults to 'max5')
#   CLAUDE_STATUS_INFO_MODE   - Info display: none (default), emoji, or text
class ClaudeStatusLine
  # Configuration
  DEFAULT_DISPLAY_MODE = :colors
  DEFAULT_INFO_MODE = :none

  # Constants
  SESSION_DURATION_HOURS = 5

  # Emoji mappings for info mode
  EMOJIS = {
    directory: "📁",
    git: "🔀",
    model: "🦾",
    tokens: "📓",
    messages: "✏️",
    time: "⏱️"
  }.freeze

  # Plan limits mapping (from Claude Monitor's plans.py)
  PLAN_LIMITS = {
    'pro' => { tokens: 19_000, messages: 250 },         # Pro plan
    'max5' => { tokens: 88_000, messages: 1_000 },      # Max5 plan
    'max20' => { tokens: 220_000, messages: 2_000 },    # Max20 plan
    'custom' => { tokens: 44_000, messages: 250 },      # Custom plan

    # Aliases and variations
    'max' => { tokens: 88_000, messages: 1_000 },       # Alias for max5
  }.freeze

  def self.detect_plan
    # Check environment variables first (multiple options for flexibility)
    plan_from_env = ENV['CLAUDE_STATUS_PLAN'] || ENV['CLAUDE_PLAN'] || ENV['CLAUDE_CODE_PLAN']
    return plan_from_env if plan_from_env && PLAN_LIMITS.key?(plan_from_env)

    # Check settings.json
    settings_file = File.expand_path('~/.claude/settings.json')
    if File.exist?(settings_file)
      begin
        settings = JSON.parse(File.read(settings_file))
        plan_from_settings = settings['model']
        return plan_from_settings if plan_from_settings && PLAN_LIMITS.key?(plan_from_settings)
      rescue JSON::ParserError, Errno::ENOENT
        # Continue to fallback
      end
    end

    'max' # Default to max plan
  end

  def self.get_limits(plan = nil)
    plan ||= detect_plan
    PLAN_LIMITS[plan] || PLAN_LIMITS['max']
  end

  # Progress bar colors based on percentage
  PROGRESS_COLORS = {
    green: "\033[32m",
    yellow: "\033[33m",
    red: "\033[31m",
    bright_red: "\033[1;31m"
  }.freeze

  # Color schemes
  COLOR_SCHEMES = {
    colors: {
      directory: "\033[38;5;51m",    # Soft sky blue
      model: "\033[38;5;105m",        # Soft pink/magenta
      tokens: "\033[38;5;141m",       # Soft cyan
      messages: "\033[38;5;147m",     # Soft green
      time: "\033[38;5;220m",         # Soft yellow
      git_clean: "\033[38;5;154m",    # Soft green
      git_dirty: "\033[38;5;222m",    # Soft peach/orange
      gray: "\033[90m",
      reset: "\033[0m"
    },
    minimal: {
      directory: "\033[38;5;250m",
      model: "\033[38;5;248m",
      tokens: "\033[38;5;248m",
      messages: "\033[38;5;248m",
      time: "\033[38;5;248m",
      git_clean: "\033[38;5;248m",
      git_dirty: "\033[38;5;248m",
      gray: "\033[90m",
      reset: "\033[0m"
    },
    background: {
      directory: "\033[44m\033[37m",     # Blue bg, white text
      model: "\033[45m\033[37m",         # Magenta bg, white text
      tokens: "\033[46m\033[30m",        # Cyan bg, black text
      messages: "\033[42m\033[30m",      # Green bg, black text
      time: "\033[43m\033[30m",          # Yellow bg, black text
      git_clean: "\033[42m\033[37m",           # Bold green
      git_dirty: "\033[43m\033[37m",           # Bold yellow
      gray: "\033[90m",
      reset: "\033[0m"
    }
  }.freeze

  def initialize
    @input_data = JSON.parse($stdin.read)
    @current_dir = @input_data.dig('workspace', 'current_dir') || @input_data['cwd']
    @model_name = @input_data.dig('model', 'display_name')
    @dir_name = File.basename(@current_dir) if @current_dir
    @display_mode = (ENV['CLAUDE_STATUS_DISPLAY_MODE']&.to_sym || DEFAULT_DISPLAY_MODE)
    @info_mode = (ENV['CLAUDE_STATUS_INFO_MODE']&.to_sym || DEFAULT_INFO_MODE)
    @colors = COLOR_SCHEMES[@display_mode] || COLOR_SCHEMES[DEFAULT_DISPLAY_MODE]

    # Session stats
    @lines_added = @input_data.dig('cost', 'total_lines_added') || 0
    @lines_removed = @input_data.dig('cost', 'total_lines_removed') || 0
    @duration_ms = @input_data.dig('cost', 'total_duration_ms') || 0

    # Auto-detect plan and set limits
    @plan = self.class.detect_plan
    @limits = self.class.get_limits(@plan)
  end

  def generate
    parts = build_status_parts

    # Ajouter les barres d'usage sur la même ligne
    usage_bar_parts = build_usage_bars_inline
    parts.concat(usage_bar_parts) if usage_bar_parts

    join_parts(parts)
  end

  def usage_bars
    nil # Plus utilisé, tout est sur une ligne
  end

  private

  def build_status_parts
    if @display_mode == :background
      [
        format_with_info(" #{@dir_name} ", :directory),
        git_info_colored_with_info,
        format_with_info(" #{@model_name} ", :model),
        format_session_duration,
        format_lines_changed,
        format_context_bar,
        format_with_info(" #{calculate_usage[:reset_time]} ", :time)
      ].compact
    else
      [
        format_with_info("#{@dir_name}/", :directory),
        git_info_colored_with_info,
        format_with_info(@model_name, :model),
        format_session_duration,
        format_lines_changed,
        format_context_bar
      ].compact
    end
  end

  def format_context_bar
    context_pct = calculate_context_percentage
    return nil if context_pct <= 0

    bar = create_progress_bar_compact(context_pct, 8)
    color = color_for_percentage(context_pct)
    "#{@colors[:gray]}ctx #{bar} #{color}#{context_pct}%#{@colors[:reset]}"
  end

  def calculate_context_percentage
    transcript_path = @input_data['transcript_path']
    return 0 unless transcript_path && File.exist?(transcript_path)

    max_tokens = 200_000
    tokens = 0

    File.foreach(transcript_path) do |line|
      next if line.strip.empty?
      begin
        data = JSON.parse(line)
        next if data['isSidechain'] == true
        next if data['isApiErrorMessage'] == true
        usage = data.dig('message', 'usage')
        next unless usage

        tokens = (usage['input_tokens'] || 0) +
                 (usage['cache_read_input_tokens'] || 0) +
                 (usage['cache_creation_input_tokens'] || 0)
      rescue JSON::ParserError
        next
      end
    end

    ((tokens.to_f / max_tokens) * 100).round
  rescue StandardError
    0
  end

  def format_session_duration
    return nil if @duration_ms <= 0
    total_seconds = @duration_ms / 1000
    hours = total_seconds / 3600
    minutes = (total_seconds % 3600) / 60

    duration_str = hours > 0 ? "#{hours}h#{minutes}m" : "#{minutes}m"
    "#{@colors[:gray]}#{duration_str}#{@colors[:reset]}"
  end

  def format_lines_changed
    return nil if @lines_added == 0 && @lines_removed == 0
    parts = []
    parts << "#{PROGRESS_COLORS[:green]}+#{@lines_added}#{@colors[:reset]}" if @lines_added > 0
    parts << "#{PROGRESS_COLORS[:red]}-#{@lines_removed}#{@colors[:reset]}" if @lines_removed > 0
    parts.join(' ')
  end

  def usage_parts
    usage = calculate_usage
    [
      colorize(usage[:tokens], :tokens),
      colorize(usage[:messages], :messages),
      colorize(usage[:reset_time], :time)
    ]
  end

  def usage_parts_with_padding
    usage = calculate_usage
    [
      colorize(" #{usage[:tokens]} ", :tokens),
      colorize(" #{usage[:messages]} ", :messages),
      colorize(" #{usage[:reset_time]} ", :time)
    ]
  end

  def usage_parts_with_info
    usage = calculate_usage
    [
      format_with_info(usage[:tokens], :tokens),
      format_with_info(usage[:messages], :messages),
      format_with_info(usage[:reset_time], :time)
    ]
  end

  def usage_parts_with_padding_and_info
    usage = calculate_usage
    [
      format_with_info_and_padding(usage[:tokens], :tokens),
      format_with_info_and_padding(usage[:messages], :messages),
      format_with_info_and_padding(usage[:reset_time], :time)
    ]
  end

  def join_parts(parts)
    if @display_mode == :background
      parts.join(' ')
    else
      separator = "#{@colors[:gray]}·#{@colors[:reset]}"
      parts.join(" #{separator} ")
    end
  end

  def colorize(text, color)
    return '' unless text
    "#{@colors[color]}#{text}#{@colors[:reset]}"
  end

  def format_with_info(text, type)
    return colorize(text, type) unless text

    case @info_mode
    when :emoji
      emoji = EMOJIS[type]
      if @display_mode == :background
        colorize("#{emoji}#{text} ", type)
      else
        colorize("#{emoji} #{text} ", type)
      end
    when :text
      suffix = get_text_suffix(type)
      colorize("#{text}#{suffix}", type)
    else
      colorize(text, type)
    end
  end

  def format_with_info_and_padding(text, type)
    return colorize(" #{text} ", type) unless text

    case @info_mode
    when :emoji
      emoji = EMOJIS[type]
      colorize("#{emoji} #{text} ", type)
    when :text
      suffix = get_text_suffix(type)
      colorize(" #{text}#{suffix} ", type)
    else
      colorize(" #{text} ", type)
    end
  end

  def get_text_suffix(type)
    case type
    when :tokens
      ""  # Raccourci - pas de suffix
    when :messages
      ""  # Raccourci - pas de suffix
    when :time
      ""  # Raccourci - pas de suffix
    else
      ""
    end
  end

  def git_info_colored_with_info
    info = git_info
    return nil unless info

    color = info.match?(/[?+!↑↓]/) ? :git_dirty : :git_clean

    case @info_mode
    when :emoji
      emoji = EMOJIS[:git]
      if @display_mode == :background
        colorize("#{emoji}#{info} ", color)
      else
        colorize("#{emoji} #{info}", color)
      end
    else
      # No text suffix for git info as requested
      if @display_mode == :background
        colorize("#{info} ", color)
      else
        colorize(info, color)
      end
    end
  end

  def git_info
    return nil unless @current_dir && Dir.exist?(File.join(@current_dir, '.git'))

    Dir.chdir(@current_dir) do
      branch = `git rev-parse --abbrev-ref HEAD 2>/dev/null`.strip
      return nil if branch.empty?

      indicators = build_git_indicators
      " #{branch}#{indicators}"
    end
  rescue
    nil
  end

  def build_git_indicators
    status = `git status --porcelain 2>/dev/null`.strip
    branch = `git rev-parse --abbrev-ref HEAD 2>/dev/null`.strip
    ahead_behind = `git rev-list --left-right --count origin/#{branch}...#{branch} 2>/dev/null`.strip

    indicators = ''
    indicators += '?' if status.match?(/^\?\?/)
    indicators += '+' if status.match?(/^[AM]/)
    indicators += '!' if status.match?(/^[MD]/)

    if ahead_behind.match(/^(\d+)\s+(\d+)$/)
      behind, ahead = ahead_behind.split.map(&:to_i)
      indicators += "↑#{ahead}" if ahead > 0
      indicators += "↓#{behind}" if behind > 0
    end

    indicators
  end

  def calculate_usage
    entries = load_usage_entries
    return default_usage if entries.empty?

    blocks = create_session_blocks(entries)
    current_block = find_active_block(blocks)
    return default_usage unless current_block

    format_usage_data(current_block)
  end

  def load_usage_entries
    project_dir = File.expand_path('~/.claude/projects')
    return [] unless Dir.exist?(project_dir)

    cutoff_time = Time.now - (96 * 3600) # 4 days like Claude Monitor
    processed_hashes = Set.new
    entries = []

    Dir.glob(File.join(project_dir, "**/*.jsonl")).each do |file|
      entries.concat(parse_jsonl_file(file, cutoff_time, processed_hashes))
    end

    entries.sort_by!(&:first)
  end

  def parse_jsonl_file(file, cutoff_time, processed_hashes)
    entries = []

    File.foreach(file) do |line|
      next if line.strip.empty?

      begin
        data = JSON.parse(line)
        entry = process_jsonl_entry(data, cutoff_time, processed_hashes)
        entries << entry if entry
      rescue JSON::ParserError, ArgumentError
        next
      end
    end

    entries
  end

  def process_jsonl_entry(data, cutoff_time, processed_hashes)
    # Time filtering
    timestamp = parse_timestamp(data['timestamp'])
    return nil unless timestamp && timestamp >= cutoff_time

    # Deduplication
    hash = unique_hash(data)
    if hash && processed_hashes.include?(hash)
      return nil
    end

    # Token extraction and validation
    tokens = extract_tokens(data)
    individual_tokens = tokens.reject { |k, _| k == :total_tokens }
    return nil if individual_tokens.values.all? { |v| v <= 0 }

    processed_hashes.add(hash) if hash
    [timestamp, tokens[:total_tokens]]
  end

  def parse_timestamp(timestamp_str)
    return nil unless timestamp_str
    DateTime.parse(timestamp_str).to_time
  rescue ArgumentError
    nil
  end

  def unique_hash(data)
    message_id = data['message_id'] || data.dig('message', 'id')
    request_id = data['requestId'] || data['request_id']
    "#{message_id}:#{request_id}" if message_id && request_id
  end

  def extract_tokens(data)
    tokens = { input_tokens: 0, output_tokens: 0, cache_creation_tokens: 0, cache_read_tokens: 0, total_tokens: 0 }

    sources = token_sources(data)

    sources.each do |source|
      next unless source.is_a?(Hash)

      input = extract_token_field(source, %w[input_tokens inputTokens prompt_tokens])
      output = extract_token_field(source, %w[output_tokens outputTokens completion_tokens])
      cache_creation = extract_token_field(source, %w[cache_creation_tokens cache_creation_input_tokens cacheCreationInputTokens])
      cache_read = extract_token_field(source, %w[cache_read_input_tokens cache_read_tokens cacheReadInputTokens])

      if input > 0 || output > 0
        tokens.merge!({
          input_tokens: input,
          output_tokens: output,
          cache_creation_tokens: cache_creation,
          cache_read_tokens: cache_read,
          total_tokens: input + output
        })
        break
      end
    end

    tokens
  end

  def token_sources(data)
    sources = []
    is_assistant = data['type'] == 'assistant'

    if is_assistant
      sources << data.dig('message', 'usage') if data.dig('message', 'usage').is_a?(Hash)
      sources << data['usage'] if data['usage'].is_a?(Hash)
    else
      sources << data['usage'] if data['usage'].is_a?(Hash)
      sources << data.dig('message', 'usage') if data.dig('message', 'usage').is_a?(Hash)
    end

    sources << data
    sources.compact
  end

  def extract_token_field(source, field_names)
    field_names.each do |field|
      value = source[field]
      return value.to_i if value && value > 0
    end
    0
  end

  def create_session_blocks(entries)
    return [] if entries.empty?

    blocks = []
    current_block = nil

    entries.each do |timestamp, tokens|
      if new_block_needed?(current_block, timestamp)
        blocks << current_block if current_block
        current_block = new_session_block(timestamp)
      end

      add_to_block(current_block, timestamp, tokens)
    end

    blocks << current_block if current_block
    blocks
  end

  def new_block_needed?(current_block, timestamp)
    return true unless current_block

    timestamp >= current_block[:end_time] ||
      (current_block[:last_timestamp] &&
       (timestamp - current_block[:last_timestamp]) >= SESSION_DURATION_HOURS * 3600)
  end

  def new_session_block(timestamp)
    start_time = round_to_hour(timestamp)
    {
      start_time: start_time,
      end_time: start_time + (SESSION_DURATION_HOURS * 3600),
      total_tokens: 0,
      message_count: 0,
      first_timestamp: timestamp,
      last_timestamp: nil
    }
  end

  def add_to_block(block, timestamp, tokens)
    return unless timestamp >= block[:start_time] && timestamp < block[:end_time]

    block[:total_tokens] += tokens
    block[:message_count] += 1
    block[:last_timestamp] = timestamp
  end

  def round_to_hour(timestamp)
    utc = timestamp.utc
    Time.new(utc.year, utc.month, utc.day, utc.hour, 0, 0, 0)
  end

  def find_active_block(blocks)
    current_time = Time.now

    # Mark active blocks
    blocks.each { |block| block[:is_active] = block[:end_time] > current_time }

    # Return first active block (Claude Monitor logic)
    blocks.find { |block| block[:is_active] } ||
      blocks.max_by { |block| block[:last_timestamp] || block[:first_timestamp] }
  end

  def format_usage_data(block)
    current_time = Time.now
    seconds_until_reset = [(block[:end_time] - current_time).to_i, 0].max
    hours = seconds_until_reset / 3600
    minutes = (seconds_until_reset % 3600) / 60

    token_pct = ((block[:total_tokens].to_f / @limits[:tokens]) * 100).round
    msg_pct = ((block[:message_count].to_f / @limits[:messages]) * 100).round

    {
      tokens: format_with_bar("tokens", block[:total_tokens], @limits[:tokens], token_pct),
      messages: format_with_bar("messages", block[:message_count], @limits[:messages], msg_pct),
      reset_time: "#{hours}h#{minutes}m"
    }
  end

  def format_with_bar(label, current, limit, pct)
    current_display = current >= 10000 ? "#{(current / 1000.0).round(1)}k" : current.to_s
    limit_display = limit >= 1000 ? "#{limit / 1000}k" : limit.to_s
    bar = create_progress_bar_compact(pct, 8)
    color = color_for_percentage(pct)
    "#{label} #{bar} #{color}#{pct}%#{@colors[:reset]}"
  end

  def format_count(current, limit)
    current_display = current >= 10000 ? "#{(current / 1000.0).round(1)}k" : current.to_s
    limit_display = limit >= 1000 ? "#{limit / 1000}k" : limit.to_s
    "#{current_display}/#{limit_display}"
  end

  def default_usage
    {
      tokens: "0/88k",
      messages: "0/1000",
      reset_time: "5h0m"
    }
  end

  # Progress bar helpers
  def color_for_percentage(pct)
    return PROGRESS_COLORS[:bright_red] if pct >= 90
    return PROGRESS_COLORS[:red] if pct >= 75
    return PROGRESS_COLORS[:yellow] if pct >= 50
    PROGRESS_COLORS[:green]
  end

  def create_progress_bar(percentage, width = 10)
    filled = (percentage.to_f / 100 * width).round
    empty = width - filled
    color = color_for_percentage(percentage)
    # Utiliser des caractères plus fins et élégants
    "#{@colors[:gray]}[#{color}#{'━' * filled}#{@colors[:gray]}#{'─' * empty}]#{@colors[:reset]}"
  end

  def fetch_api_usage
    token = get_oauth_token
    return nil unless token

    require 'net/http'
    require 'uri'

    uri = URI('https://api.anthropic.com/api/oauth/usage')
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = 2
    http.read_timeout = 2

    request = Net::HTTP::Get.new(uri)
    request['Authorization'] = "Bearer #{token}"
    request['anthropic-beta'] = 'oauth-2025-04-20'

    response = http.request(request)
    return nil unless response.code == '200'

    JSON.parse(response.body)
  rescue StandardError
    nil
  end

  def get_oauth_token
    result = `security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null`.strip
    return nil if result.empty?

    data = JSON.parse(result)
    data.dig('claudeAiOauth', 'accessToken')
  rescue StandardError
    nil
  end

  def format_api_reset_time(reset_at_str)
    return nil unless reset_at_str
    reset_time = DateTime.parse(reset_at_str).to_time
    diff_seconds = (reset_time - Time.now).to_i
    return nil if diff_seconds <= 0

    days = diff_seconds / 86400
    hours = (diff_seconds % 86400) / 3600
    minutes = (diff_seconds % 3600) / 60

    if days > 0
      "#{days}d#{hours}h"
    elsif hours > 0
      "#{hours}h#{minutes.to_s.rjust(2, '0')}m"
    else
      "#{minutes}m"
    end
  rescue StandardError
    nil
  end

  def build_usage_bars_inline
    api_data = fetch_api_usage
    return nil unless api_data

    five_hour_pct = (api_data.dig('five_hour', 'utilization') || 0).round
    five_hour_reset = format_api_reset_time(api_data.dig('five_hour', 'resets_at'))
    seven_day_pct = (api_data.dig('seven_day', 'utilization') || 0).round
    seven_day_reset = format_api_reset_time(api_data.dig('seven_day', 'resets_at'))

    five_bar = create_progress_bar_compact(five_hour_pct)
    five_color = color_for_percentage(five_hour_pct)
    seven_bar = create_progress_bar_compact(seven_day_pct)
    seven_color = color_for_percentage(seven_day_pct)

    # Format compact : label(temps) [barre] %
    five_label = five_hour_reset ? "5h(#{five_hour_reset})" : "5h"
    seven_label = seven_day_reset ? "7d(#{seven_day_reset})" : "7d"

    five_part = "#{@colors[:gray]}#{five_label} #{five_bar} #{five_color}#{five_hour_pct}%#{@colors[:reset]}"
    seven_part = "#{@colors[:gray]}#{seven_label} #{seven_bar} #{seven_color}#{seven_day_pct}%#{@colors[:reset]}"

    [five_part, seven_part]
  rescue StandardError
    nil
  end

  def create_progress_bar_compact(percentage, width = 10)
    filled = (percentage.to_f / 100 * width).round
    empty = width - filled
    color = color_for_percentage(percentage)
    "#{@colors[:gray]}[#{color}#{'█' * filled}#{@colors[:gray]}#{'░' * empty}]#{@colors[:reset]}"
  end

  def build_usage_bars
    # Deprecated - kept for compatibility
    nil
  end
end

# Execute
status = ClaudeStatusLine.new
puts status.generate
