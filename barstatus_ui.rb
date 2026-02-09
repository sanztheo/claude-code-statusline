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
  { key: 'display_mode', label: 'Mode affichage', type: :enum, options: %w[compact full minimal] },
  { key: 'bar_style', label: 'Style barre', type: :enum, options: %w[tqdm blocks percent_only] },
  { key: 'show_5h', label: 'Afficher 5h', type: :bool },
  { key: 'show_7d', label: 'Afficher 7d', type: :bool },
  { key: 'show_ctx', label: 'Afficher ctx', type: :bool },
  { key: 'show_git', label: 'Afficher git', type: :bool },
  { key: 'show_duration', label: 'Afficher duree', type: :bool }
].freeze

class BarstatusMenu
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
        puts "\nConfiguration enregistree dans #{CONFIG_PATH}"
        return 0
      when :cancel
        puts "\nAnnule (aucune sauvegarde)."
        return 0
      when :ctrl_c
        puts "\nInterrompu."
        return 130
      end
    end
  ensure
    # Safety net in case terminal mode gets stuck after an interruption.
    system('stty sane >/dev/null 2>&1')
  end

  private

  def load_config
    return DEFAULT_CONFIG.dup unless File.exist?(CONFIG_PATH)

    parsed = JSON.parse(File.read(CONFIG_PATH))
    sanitize_config(parsed)
  rescue JSON::ParserError
    @warning = "Fichier config invalide: defaults charges."
    DEFAULT_CONFIG.dup
  rescue StandardError => e
    @warning = "Lecture config impossible (#{e.class}): defaults charges."
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
    print "\e[H\e[2J"
    puts "/barstatus - Menu interactif"
    puts "-" * 54
    puts "Navigation: ↑/↓ selection | ←/→ modifier | Entree sauvegarder | q quitter"
    puts "Fallback:   k/j selection | h/l modifier"
    puts
    puts "Config: #{CONFIG_PATH}"
    puts "Etat: #{@dirty ? 'modifie (non sauvegarde)' : 'sauvegarde'}"
    puts "Alerte: #{@warning}" if @warning
    puts

    ITEMS.each_with_index do |item, idx|
      prefix = (idx == @selected_index) ? '>' : ' '
      value = display_value(item)
      puts "#{prefix} #{item[:label].ljust(20)} : #{value}"
    end
  end

  def display_value(item)
    value = @config[item[:key]]
    if item[:type] == :bool
      value ? 'true' : 'false'
    else
      value.to_s
    end
  end

  def apply_change(direction)
    item = ITEMS[@selected_index]
    key = item[:key]

    old = @config[key]

    if item[:type] == :bool
      @config[key] = direction > 0
    else
      options = item[:options]
      current_index = options.index(@config[key]) || 0
      next_index = (current_index + direction) % options.length
      @config[key] = options[next_index]
    end

    @dirty = true if old != @config[key]
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
