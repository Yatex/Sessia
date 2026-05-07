namespace :sessia do
  namespace :ai do
    desc "Generate and process due Sessia AI assistant tasks"
    task loop: :environment do
      result = Ai::ManagerLoopService.new.call
      puts result.summary
      result.errors.each { |error| warn error }
    end
  end
end
