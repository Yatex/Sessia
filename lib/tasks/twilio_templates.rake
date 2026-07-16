namespace :sessia do
  namespace :twilio do
    namespace :templates do
      desc "Print Sessia's local WhatsApp template catalog without calling Twilio"
      task dry_run: :environment do
        manager = Messaging::WhatsappTemplateManager.new
        print_template_rows(manager.dry_run, include_body: true)
      end

      desc "Create missing Sessia Content Templates in Twilio (does not submit approval or modify ENV)"
      task create: :environment do
        manager = Messaging::WhatsappTemplateManager.new
        rows = manager.create
        print_template_rows(rows)
        puts "\nCreated/existing ContentSid block (copy only after reviewing the rows):"
        puts manager.env_block(rows)
        puts "\nTemplates are not submitted for WhatsApp approval by this command."
      end

      desc "Show remote WhatsApp approval status for every configured Sessia template"
      task status: :environment do
        print_template_rows(Messaging::WhatsappTemplateManager.new.status)
      end

      desc "Compare Sessia's local catalog, ENV and remote Twilio Content Templates"
      task audit: :environment do
        print_template_rows(Messaging::WhatsappTemplateManager.new.audit)
      end

      desc "Print the WhatsApp ContentSid ENV block without modifying the environment"
      task env: :environment do
        puts Messaging::WhatsappTemplateCatalog.env_block
      end
    end
  end
end

def print_template_rows(rows, include_body: false)
  rows.each do |row|
    puts "\n#{row[:key]}/#{row[:locale]}"
    puts "  workflow:      #{row[:workflow]}"
    puts "  friendly_name: #{row[:friendly_name]}"
    puts "  category:      #{row[:category]}"
    puts "  variables:     #{Array(row[:variables]).join(', ')}"
    puts "  placeholders:  #{Array(row[:placeholders]).map { |number| "{{#{number}}}" }.join(', ')}"
    puts "  ENV:           #{row[:env_key]}"
    puts "  ContentSid:    #{row[:content_sid].presence || '-'}"
    puts "  status:        #{row[:status]}"
    puts "  body:          #{row[:body]}" if include_body
    puts "  errors:        #{Array(row[:errors]).presence&.join(', ') || '-'}"
  end
end
