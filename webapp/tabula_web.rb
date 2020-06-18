# -*- coding: utf-8 -*-
require 'cuba'
require 'cuba/render'

require 'rubygems'
require 'json'
require 'digest/sha1'
require 'json'
require 'csv'
require 'tempfile'
require 'fileutils'
require 'securerandom'
require 'java'
require 'singleton'


require_relative '../lib/tabula_java_wrapper.rb'
java_import 'java.io.ByteArrayOutputStream'
java_import 'java.util.zip.ZipEntry'
java_import 'java.util.zip.ZipOutputStream'
java_import org.apache.pdfbox.pdmodel.PDDocument
java_import org.apache.pdfbox.cos.COSDictionary
java_import org.apache.pdfbox.cos.COSName

require_relative './tabula_settings.rb'

begin
  require_relative './tabula_version.rb'
rescue LoadError
  $TABULA_VERSION = "rev#{`git rev-list --max-count=1 HEAD`.strip}"
end

require_relative '../lib/tabula_workspace.rb'
require_relative '../lib/tabula_job_executor/executor.rb'
require_relative '../lib/tabula_job_executor/jobs/generate_document_data.rb'
require_relative '../lib/tabula_job_executor/jobs/generate_thumbnails.rb'
require_relative '../lib/tabula_job_executor/jobs/detect_tables.rb'

class RegexQueryMetaData

  attr_accessor :regex_searches,:filter_area,:doc_ID
  attr_reader   :file

  include Singleton

  def initialize
    @doc_ID=String.new()
    @regex_searches=[]
    @file = nil
    @filter_area = nil
  end

  def is_new_doc(docID)
    puts !(@doc_ID == docID)
    return !(@doc_ID == docID)
  end

  def reset_for_new_doc(docID)

    @doc_ID=docID
    @regex_searches=[]

    @filter_area = nil #Page margins are initially not set

    unless @file.nil?
      @file.close() #TODO: figure out if a warning should be thrown here....
    end

    output_dir = File.join(TabulaSettings::DOCUMENTS_BASEPATH, @doc_ID)
    @file = PDDocument.load(Java::JavaIO::File.new(File.join(output_dir,'document.pdf')))



  end
end



def is_valid_pdf?(path)
  File.open(path, 'r') { |f| f.read(4) } == '%PDF'
end


regex_query_meta_data = RegexQueryMetaData.instance()

STATIC_ROOT = if defined?($servlet_context)
                File.join($servlet_context.getRealPath('/'), 'WEB-INF/webapp/static')
              else
                File.join(File.dirname(__FILE__), 'static')
              end


Cuba.plugin Cuba::Render
Cuba.settings[:render].store(:views, File.expand_path("views", File.dirname(__FILE__)))
Cuba.use Rack::MethodOverride
Cuba.use Rack::Static, root: STATIC_ROOT, urls: ["/css","/js", "/img", "/swf", "/fonts"]
Cuba.use Rack::ContentLength
Cuba.use Rack::Reloader


def upload(file)
  original_filename = file[:filename]
  file_id = Digest::SHA1.hexdigest(Time.now.to_s + original_filename) # just SHA1 of time isn't unique with multiple uploads
  file_path = File.join(TabulaSettings::DOCUMENTS_BASEPATH, file_id)

  Tabula::Workspace.instance.move_file(file[:tempfile].path, file_id, 'document.pdf')

  filepath = Tabula::Workspace.instance.get_document_path(file_id)
  job_batch = SecureRandom.uuid
  thumbnail_sizes =  [800]

  GenerateDocumentDataJob.create(:filepath => filepath,
                                 :original_filename => original_filename,
                                 :id => file_id,
                                 :thumbnail_sizes => thumbnail_sizes,
                                 :batch => job_batch)

  DetectTablesJob.create(:filepath => filepath,
                         :id => file_id,
                         :batch => job_batch)

  GenerateThumbnailJob.create(:file_id => file_id,
                              :filepath => filepath,
                              :output_dir => file_path,
                              :thumbnail_sizes => thumbnail_sizes,
                              :batch => job_batch)
  return [job_batch, file_id]
end

class InvalidTemplateError < StandardError; end
TEMPLATE_REQUIRED_KEYS = ["page", "extraction_method", "x1", "x2", "y1", "y2", "width", "height"]
def upload_template(template_file)
  template_name = template_file[:filename].gsub(/\.json$/, "").gsub(/\.tabula-template/, "")
  template_id = Digest::SHA1.hexdigest(Time.now.to_s + template_name) # just SHA1 of time isn't unique with multiple uploads
  template_filename = template_id + ".tabula-template.json"

  # validate the uploaded template, since it really could be anything.
  template_json = open(template_file[:tempfile].path, 'r'){|f| f.read }
  begin
    template_data = JSON.parse(template_json)
  rescue JSON::ParserError => e
    raise InvalidTemplateError.new("template is invalid json: #{e}")
  end

  raise InvalidTemplateError.new("template is invalid, must be an array of selection objects") unless template_data.is_a?(Array)
  raise InvalidTemplateError.new("template is invalid; a selection object is invalid") unless template_data.all?{|sel| TEMPLATE_REQUIRED_KEYS.all?{|k| sel.has_key?(k)} }

  page_count = template_data.map{|sel| sel["page"]}.uniq.size
  selection_count = template_data.size

  # write to file and to workspace
  Tabula::Workspace.instance.add_template({ "id" => template_id,
                                            "template" => template_data,
                                            "name" => template_name,
                                            "page_count" => page_count,
                                            "time" => Time.now.to_i,
                                            "selection_count" => selection_count})
  return template_id
end

Cuba.define do
  if TabulaSettings::ENABLE_DEBUG_METHODS
    require_relative './tabula_debug.rb'
    on 'debug' do
      run TabulaDebug
    end
  end


  on 'queue' do
    require_relative './tabula_job_progress.rb'
    run TabulaJobProgress
  end

  on "templates" do
    # GET  /books/ .... collection.fetch();
    # POST /books/ .... collection.create();
    # GET  /books/1 ... model.fetch();
    # PUT  /books/1 ... model.save();
    # DEL  /books/1 ... model.destroy();

    on root do
      # list them all
      on get do
        res.status = 200
        res['Content-Type'] = 'application/json'
        res.write(JSON.dump(Tabula::Workspace.instance.list_templates))
      end

      # create a template from the GUI
      on post do
        template_info = JSON.parse(req.params["model"])
        template_name = template_info["name"] || "Unnamed Template #{Time.now.to_s}"
        template_id = Digest::SHA1.hexdigest(Time.now.to_s + template_name) # just SHA1 of time isn't unique with multiple uploads
        template_filename = template_id + ".tabula-template.json"
        file_path = File.join(TabulaSettings::DOCUMENTS_BASEPATH, "..", "templates")
        # write to file
        FileUtils.mkdir_p(file_path)
        open(File.join(file_path, template_filename), 'w'){|f| f << JSON.dump(template_info["template"])}
        page_count = template_info.has_key?("page_count") ? template_info["page_count"] : template_info["template"].map{|f| f["page"]}.uniq.count
        selection_count = template_info.has_key?("selection_count") ? template_info["selection_count"] :  template_info["template"].count
        Tabula::Workspace.instance.add_template({
                                                  "id" => template_id,
                                                  "name" => template_name,
                                                  "page_count" => page_count,
                                                  "time" => Time.now.to_i,
                                                  "selection_count" => selection_count,
                                                  "template" => template_info["template"]
                                                })
        res.status = 200
        res['Content-Type'] = 'application/json'
        res.write(JSON.dump({template_id: template_id}))
      end
    end

    # upload a template from disk
    on 'upload.json' do
      if req.params['file']
        template_ids = [upload_template(req.params['file'])]
      elsif req.params['files']
        template_ids = req.params['files'].map{|f| upload_template(f)}
      end
      res.status = 200
      res['Content-Type'] = 'application/json'
      res.write(JSON.dump({template_ids: template_ids}))
    end

    on ":template_id.json" do |template_id|
      on get do
        template_name = Tabula::Workspace.instance.get_template_metadata(template_id)["name"] # TODO
        res['Content-Type'] = 'application/json'
        res['Content-Disposition'] = "attachment; filename=\"#{template_name}.tabula-template.json\""
        template_body = Tabula::Workspace.instance.get_template_body(template_id)
        res.status = 200
        res.write template_body
      end
    end
    on ":template_id" do |template_id|
      on get do
        template_metadata = Tabula::Workspace.instance.get_template_metadata(template_id) # TODO
        template_name = template_metadata["name"]
        template_body = Tabula::Workspace.instance.get_template_body(template_id)
        template_metadata["selections"] = JSON.parse template_body
        res.status = 200
        res['Content-Type'] = 'application/json'
        res.write JSON.dump(template_metadata)
      end
      on put do
        old_metadata = Tabula::Workspace.instance.get_template_metadata(template_id) # TODO
        new_metadata = old_metadata.merge(JSON.parse(req.params["model"]))
        Tabula::Workspace.instance.replace_template_metadata(template_id, new_metadata)
        res.status = 200
        res['Content-Type'] = 'application/json'
        res.write(JSON.dump({template_id: template_id}))
      end
      on delete do
        Tabula::Workspace.instance.delete_template(template_id)
        res.status = 200
        res.write ''
      end
    end
  end

  on delete do

    on 'pdf/:file_id/page/:page_number' do |file_id, page_number|
      index = Tabula::Workspace.instance.get_document_pages(file_id)
      index.find { |p| p['number'] == page_number.to_i }['deleted'] = true
      File.open(index_fname, 'w') { |f| f.write JSON.generate(index) }
      res.write '' # Firefox complains about an empty response without this.
    end

    # delete an uploaded file
    on 'pdf/:file_id' do |file_id|
      Tabula::Workspace.instance.delete_document(file_id)
      res.write '' # Firefox complains about an empty response without this.
    end

  end

  on put do
    on 'pdf/:file_id/page/:page_number' do |file_id, page_number|
      # nothing yet
    end
  end

  on get do
    on 'pdfs' do
      run Rack::File.new(TabulaSettings::DOCUMENTS_BASEPATH)
    end


    on 'documents' do
      res.status = 200
      res['Content-Type'] = 'application/json'
      res.write(JSON.dump(Tabula::Workspace.instance.list_documents))
    end

    on 'version' do
      res.write JSON.dump({api: $TABULA_VERSION})
    end

    on 'pdf/:file_id/metadata.json' do |file_id|
      res['Content-Type'] = 'application/json'
      res.write Tabula::Workspace.instance.get_document_metadata(file_id).to_json
    end

    [root, "about", "pdf/:file_id", "help", "mytemplates"].each do |paths_to_single_page_app|
      on paths_to_single_page_app do
        index = File.read("webapp/index.html")
        if ROOT_URI != ''
          index.sub!("<base href=\"/\">", "<base href=\"#{ROOT_URI}\">")
        end
        res.write index
      end
    end

  end # /get

  on post do


    on 'regex' do

      on 'reset' do
        puts req.params
        puts "In regex/reset..."
        regex_query_meta_data.reset_for_new_doc(req.params['file_path'])
        res.write ''
      end

      on 'search' do
        puts req.params
        puts "In regex/search..."

        puts regex_query_meta_data.filter_area

        regex_search = Java::TechnologyTabulaDetectors::RegexSearch.new(req.params['pattern_before'],
                                                                        req.params['include_pattern_before'],
                                                                        req.params['pattern_after'],
                                                                        req.params['include_pattern_after'],
                                                                        regex_query_meta_data.file,
                                                                        regex_query_meta_data.filter_area)

        regex_query_meta_data.regex_searches.push(regex_search)

        puts regex_query_meta_data.regex_searches

        gson = Gson::GsonBuilder.new.setFieldNamingPolicy(Gson::FieldNamingPolicy::LOWER_CASE_WITH_UNDERSCORES).create()
        res.write(gson.to_json(regex_search))
      end

      on 'check-on-resize' do
        puts 'In regex/check-on-resize'
        puts req.params

        regex_query_meta_data.filter_area = Java::TechnologyTabulaDetectors::RegexSearch::FilteredArea.new(req.params['header_scale'].to_f,
                                                                                              req.params['footer_scale'].to_f)


        puts regex_query_meta_data.filter_area

        changedQueries = []

        unless regex_query_meta_data.regex_searches.nil? || regex_query_meta_data.regex_searches.empty?
          changedQueries = Java::TechnologyTabulaDetectors::
              RegexSearch.checkSearchesOnFilterResize(regex_query_meta_data.file,
                                                      regex_query_meta_data.filter_area,
                                                      regex_query_meta_data.regex_searches)
        end

        puts 'Changed Queries:';
        puts changedQueries.length
        gson = Gson::GsonBuilder.new.setFieldNamingPolicy(Gson::FieldNamingPolicy::LOWER_CASE_WITH_UNDERSCORES).create()

        res.write(gson.to_json(changedQueries))
      end

      on 'remove-search-data' do
        puts req.params
        puts regex_query_meta_data.regex_searches
        puts 'In remove-search-data'
        removed_searches, regex_query_meta_data.regex_searches = regex_query_meta_data.regex_searches.partition {
          |search| search.getRegexBeforeTable() == req.params['pattern_before'] &&
            search.getRegexAfterTable() == req.params['pattern_after']
        }
        if removed_searches.length > 1 || removed_searches.length==0
          res.status =500
          puts removed_searches.length
          res.write('Incorrect number of searches removed:')
        else
          puts 'Removed Regex search:'
          puts removed_searches[0]

          puts 'Remaining Regex searches:'

          gson = Gson::GsonBuilder.new.setFieldNamingPolicy(Gson::FieldNamingPolicy::LOWER_CASE_WITH_UNDERSCORES).create()
          res.write(gson.to_json(removed_searches))
        end
        res.write ''
      end
    end

    on 'upload.json' do
      # Make sure this is a PDF, before doing anything

      if req.params['file'] # single upload mode. this should be deleting once if decide to enable multiple upload for realzies
        job_batch, file_id = *upload(req.params['file'])
        unless is_valid_pdf?(req.params['file'][:tempfile].path)
          res.status = 400
          res.write(JSON.dump({
            :success => false,
            :filename => req.params['file'][:filename],
            # :file_id => file_id,
            # :upload_id => job_batch,
            :error => "Sorry, the file you uploaded was not detected as a PDF. You must upload a PDF file. Please try again."
            }))
          next # halt this handler
        end

        res.write(JSON.dump([{
            :success => true,
            :file_id => file_id,
            :upload_id => job_batch
        }]))
      elsif req.params['files']
        statuses = req.params['files'].map do |file|
          if is_valid_pdf?(file[:tempfile].path)
            job_batch, file_id = *upload(file)
            {
              :filename => file[:filename],
              :success => true,
              :file_id => file_id,
              :upload_id => job_batch
            }
          else
            {
              :filename => file[:filename],
              :success => false,
              :file_id => file_id,
              :upload_id => job_batch,
              :error => "Sorry, the file you uploaded was not detected as a PDF. You must upload a PDF file. Please try again."
            }
            # next # halt this handler
          end
        end
        # if they all fail, return 400...
        res.status = 400 if(statuses.find{|a| a[:success] }.empty? )
        res.write(JSON.dump(statuses))
      else
        STDOUT.puts req.params.keys.inspect
      end
    end

    on "pdf/:file_id/data" do |file_id|
      pdf_path = Tabula::Workspace.instance.get_document_path(file_id)

      puts 'DO I GET HERE BEFORE THE CRASH??'

      coords = JSON.load(req.params['coords'])

      puts 'COORDS:'
      puts coords

      coords.sort_by! do |coord_set|
        puts 'coord_set:'
        puts coord_set
        [
         coord_set['page'],
         [coord_set['y1'], coord_set['y2']].min.to_i / 10,
         [coord_set['x1'], coord_set['x2']].min
        ]
      end

      extraction_method = JSON.load(req.params['extraction_method'])

      options = {"extraction_method" => extraction_method}


      puts req.params

      tables = Tabula.extract_tables(pdf_path, coords, options)

      filename =  if req.params['new_filename'] && req.params['new_filename'].strip.size
                    basename = File.basename(req.params['new_filename'], File.extname(req.params['new_filename']))
                    "tabula-#{basename}"
                  else
                    "tabula-#{file_id}"
                  end

      case req.params['format']
        when 'csv'
          res['Content-Type'] = 'text/csv'
          res['Content-Disposition'] = "attachment; filename=\"#{filename}.csv\""
          puts 'TABLES'
          puts tables
          tables.each do |table|
            res.write table.to_csv
            puts table.to_csv
          end
      when 'tsv'
        res['Content-Type'] = 'text/tab-separated-values'
        res['Content-Disposition'] = "attachment; filename=\"#{filename}.tsv\""
        tables.each do |table|
          res.write table.to_tsv
        end
      when 'zip'
        res['Content-Disposition'] = "attachment; filename=\"#{filename}.zip\""

        # I hate Java, Ruby, JRuby, Zip files, C, umm, computers, Linux, GNU,
        # parrots-as-gifts, improper climate-control settings, tar, gunzip,
        # streams, computers, did I say that already? ugh.
        baos = ByteArrayOutputStream.new;
        zos = ZipOutputStream.new baos

        tables.each_with_index do |table, index|
          # via https://stackoverflow.com/questions/23612864/create-a-zip-file-in-memory
          # /* File is not on the disk, test.txt indicates
          #    only the file name to be put into the zip */
          entry = ZipEntry.new("#{filename}-#{index}.csv")

          # /* use more Entries to add more files
          #    and use closeEntry() to close each file entry */
          zos.putNextEntry(entry)
          zos.write(table.to_csv.to_java_bytes) # lol java BITES...
          zos.closeEntry()
        end
        zos.finish
        # you know what, I changed my mind about JRuby.
        # this is actually way easier than it would be in MRE/CRuby.
        # ahahaha. I get the last laugh now.

        res.write String.from_java_bytes(baos.to_byte_array)
        when 'script'

          puts 'USER DRAWN SELECTIONS...'
          puts req.params['user_drawn_selections']
          puts 'COORDS'
          puts req.params['coords']

        gson = Gson::GsonBuilder.new.setFieldNamingPolicy(Gson::FieldNamingPolicy::LOWER_CASE_WITH_UNDERSCORES).create()

        sanitized_query_data = Array.new

        regex_query_meta_data.regex_searches.each{ |x|

          raw_search_data =JSON.parse(gson.to_json(x))

          sanitized_query_data.push({pattern_before: raw_search_data["_regex_before_table"]["pattern"],
                                     include_pattern_before: raw_search_data["_include_regex_before_table"],
                                     pattern_after: raw_search_data["_regex_after_table"]["pattern"],
                                     include_pattern_after: raw_search_data["_include_regex_after_table"]})
        }

        puts sanitized_query_data

        regex_cli_option = JSON.generate({queries: sanitized_query_data});

        puts regex_cli_option.to_json

        regex_cli_string = ""
        if !regex_query_meta_data.regex_searches.empty?
          regex_cli_string="-x '#{regex_cli_option}'"
        end

        drawn_boxes_cli_string=""

        user_drawn_selections = JSON.load(req.params['user_drawn_selections'])

        if user_drawn_selections.nil?
          user_drawn_selections = []
        end

        user_drawn_selections.sort_by! do |sel_set|
            [
            sel_set['page'],
            [sel_set['y1'], sel_set['y2']].min.to_i / 10,
            [sel_set['x1'], sel_set['x2']].min
            ]
          end

        user_drawn_selections.each do |s|
          drawn_boxes_cli_string = drawn_boxes_cli_string +
            " -a #{s['y1'].round(3)},#{s['x1'].round(3)},#{s['y2'].round(3)},#{s['x2'].round(3)} -p #{s['page']}"
        end

       extraction_cli_string = ''

       coords.each do |c|
         extraction_cli_string = if c['extraction_method'] == "original"
                                   "--no-spreadsheet"
                                 elsif c['extraction_method'] == "spreadsheet"
                                   "--spreadsheet"
                                 elsif c['extraction_method'] == "stream"
                                   "--stream"
                                 elsif c['extraction_method'] == "lattice"
                                   "--lattice"
                                  elsif c['extraction_method'] == "wordwrapped"
                                    "--wordwrapped"
                                 else
                                      ' ' #Non-empty string
                                 end
         break
       end


       margins = JSON.load(req.params['margin_scale'])

       margin_cli_string ="-m '#{margins}'"
          # Write shell script of tabula-extractor commands.  $1 takes
        # the name of a file from the command line and passes it
        # to tabula-extractor so the script can be reused on similar pdfs.
        res['Content-Type'] = 'application/x-sh'
        res['Content-Disposition'] = "attachment; filename=\"#{filename}.sh\""

        res.write "java -jar tabula-java.jar #{extraction_cli_string} #{regex_cli_string} #{drawn_boxes_cli_string} #{margin_cli_string} \"$1\" \n"

      when 'bbox'
        # Write json representation of bounding boxes and pages for
        # use in OCR and other back ends.
        res['Content-Type'] = 'application/json'
        res['Content-Disposition'] = "attachment; filename=\"#{filename}.json\""
        res.write coords.to_json
      when 'json'
        # Write json representation of bounding boxes and pages for
        # use in OCR and other back ends.
        res['Content-Type'] = 'application/json'
        res['Content-Disposition'] = "attachment; filename=\"#{filename}.json\""

        # start JSON array
        res.write  "["
        tables.each_with_index do |table, index|
          res.write ", " if index > 0
          res.write table.to_json[0...-1] + ", \"spec_index\": #{table.spec_index}}"
        end

        # end JSON array
        res.write "]"
     else
        res['Content-Type'] = 'application/json'

        # start JSON array
        res.write  "["
        tables.each_with_index do |table, index|
          res.write ", " if index > 0
          res.write table.to_json[0...-1] + ", \"spec_index\": #{table.spec_index}}"
        end

        # end JSON array
        res.write "]"
      end
    end
  end
end
