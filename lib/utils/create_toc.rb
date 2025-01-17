# frozen_string_literal: true

require_relative '../process_manager.rb'
require_relative '../base_process.rb'
require_relative '../config_manager.rb'
require_relative './adoc.rb'
require_relative './hash.rb'
require_relative '../log/log.rb'
require 'json'
require 'nokogiri'
require 'fileutils'

CM = Toolchain::ConfigManager.instance

module Toolchain
  module Adoc
    ##
    class CreateTOC
      def initialize
        @multipage_level = CM.get('asciidoc.multipage_level')
        @default_json_filepath = File.join(
          ::Toolchain.build_path,
          CM.get('toc.json_file'))
        @default_html_filepath = File.join(
          ::Toolchain.build_path,
          CM.get('toc.html_file'))
      end

      ##
      # Creates a TOC JSON file from an Asciidoctor document +document+
      # Default JSON path is taken from +ConfigManager+.
      #
      # Saves toc as json tree +toc_json+
      # Saves toc as html code +html_fragment+
      # Returns path to created JSON file +json_filepath+,
      # path to creted HTML fragment file +html_path+ and the TOC Has +toc_hash+
      #
      def run(
        document,
        json_filepath = @default_json_filepath,
        html_filepath = @default_html_filepath
      )
        # TODO: this runs too often. e.g. uncomment stage_log line below and see what happens
        catalog = document.catalog
        FileUtils.mkdir_p(File.dirname(@default_json_filepath))
        FileUtils.mkdir_p(File.dirname(@default_html_filepath))
        # stage_log(:build, 'Inject TOC into ' + File.basename(html_filepath))
        stack = [OpenStruct.new(id: 'root', level: -1, children: [])]
        ancestors = []

        # for all headings in the adoc document do
        catalog[:refs].keys.each do |r|
          ref = catalog[:refs][r]
          next unless ref.is_a? Asciidoctor::Section
          level = ref.level
          title = ref.title
          id = ref.id
          attribs = ref.instance_variable_get(:@attributes)

          # skip discrete headings and headings with a level too high
          is_discrete = attribs&.key?(1) && (attribs&.fetch(1) == 'discrete')
          next if is_discrete || title.nil?
          current = OpenStruct.new(
            id: id,
            level: level,
            label: nil,
            # remove style tags that asciidoctor leaves in titles
            title: title.gsub(%r{<\/?[^>]*>}, ''),
            parent: nil,
            parents: [],
            children: []
          )
          while level <= stack.last.level
            stack.pop
            ancestors.pop
          end
          current.parent = stack.last
          ancestors << current.parent.id
          founder = ancestors[@multipage_level] || current.id

          # add current element to it's parent's children list
          current.parent.children << current

          stack.each do |sect|
            title = sect.title
            next if title.nil?
            current.parents << title
            current.label = title if ['REST', 'WPP v1', 'WPP v2'].any? do |kw|
              title.include?(kw)
            end
          end
          # replace parent object now with it's id to avoid loops
          current.parent = current.parent.id
          current.founder = founder
          stack.push current
        end

        # first element of the stack contains the final TOC tree
        toc_openstruct = stack.first

        # create JSON from TOC tree
        toc_hash = ::Toolchain::Hash.openstruct_to_hash(toc_openstruct)
        toc_json = JSON.pretty_generate(toc_hash)
        File.open(json_filepath, 'w+') do |json_file|
          json_file.write(toc_json)
        end

        # create Nokogiri HTML document Object from TOC tree
        # class and id same as default asciidoctor html5 converter with enabled TOC for drop-in replacement
        toc_html_dom = Nokogiri::HTML.fragment(
          '<div id="toc" class="toc2"></div>' + "\n")

        toc_html_dom.at_css('#toc') << generate_html_from_toc(
          toc_openstruct.children)

        # convert Nokogiri HTML Object to string
        toc_html_string = toc_html_dom.to_xhtml(indent: 3)
        File.open(html_filepath, 'w+') do |html_file|
          html_file.write(toc_html_string)
        end
        return json_filepath, html_filepath, toc_hash
      end

      ##
      # Tick all checkboxes of ancestors of current page
      # Requires +page_id+ and Nokogiri Table of Content +toc_document+
      # Returns modified TOC +toc_document+
      #
      def tick_toc_checkboxes(page_id, toc_document)
        selector = '#toc_li_' + page_id
        list_element = toc_document.at_css(selector)
        while list_element
          break unless list_element.name == 'li'
          begin
            cb = list_element.at_css('> input')
            cb.set_attribute('checked','')
            selector = '#' + list_element.parent.parent.attr('id')
            list_element = toc_document.at_css selector
          rescue StandardError => _e
            break
          end
        end
        return toc_document
      end

      ## Recursivelz generates a HTML fragment for the Table Of Content
      # Takes OpenStruct of +toc_elements+ as input
      # Returns HTML code fragment as string Nokogiri Object +fragment+
      #
      def generate_html_from_toc(toc_elements)
        fragment = Nokogiri::HTML.fragment('<ul></ul>')
        toc_elements.each do |e|
          root_file = e.founder == 'root' ? '' : e.founder + '.html'
          level = e.level || 0
          id = e.id
          disabled = ''
          disabled = ' disabled' if e.children.empty?

          fragment_string = Nokogiri::HTML.fragment(
            %(<li id="toc_li_#{id}" data-level="#{level}"></li>)
          )

          link = %(<a href="#{root_file}#{(e.founder == id ? '' : '#' + id)}">#{e.title}</a>)
          fragment_string.at('li') << (
            "\n" + %(<input id="toc_cb_#{id}" type="checkbox"#{disabled}>) +
              %(<label for="toc_cb_#{id}">#{link}</label>) + "\n"
          )

          # if element has child elements, add them to current list item
          fragment_string.at('li') << generate_html_from_toc(e.children) unless e.children.empty?
          fragment.at('ul') << fragment_string
        end
        return fragment
      end
    end
  end
end
