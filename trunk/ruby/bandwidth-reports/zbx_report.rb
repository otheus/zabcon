#!/usr/bin/ruby

require 'date'
require 'rubygems'
require 'active_record'
require 'ruport'
require 'net/smtp'
require 'tmail'

PROGRAM = File.basename($0)

#global variables
#Do we ant to enable debugging?
$debug=false

  def getreport(hostname,date,days,interfaces)

    
		# This is the query string we use to generate the report.  It makes use of
		# the stored procedure total_from_delta
		query_str = <<EOQ
create temporary table temp_totals
select host, interface, max(inbound) as inbound, max(outbound) as outbound, (max(inbound) + max(outbound)) as total from
(( select host, interface, total_from_delta(itemid,'#{date}',#{days}) as inbound, NULL as outbound
  from net_ifgroups where host='#{hostname}' and type='inbound' and
  interface in (#{"'"+interfaces.join("','")+"'"}))
 union
  (select host, interface, NULL as inbound, total_from_delta(itemid,'#{date}',#{days}) as outbound
  from net_ifgroups where host='#{hostname}' and type='outbound' and
  interface in (#{"'"+interfaces.join("','")+"'"}))) as t1
 group by interface
EOQ

   puts query_str if $debug

   results = ActiveRecord::Base.connection.execute(query_str)
  end

ActiveRecord::Base.establish_connection(
  :adapter => "mysql",
  :host => "",
  :username => "",
  :database => ""
)

class Temp_Totals < ActiveRecord::Base 
  set_table_name "temp_totals"
  acts_as_reportable

  def inbound_readable
    case
      when inbound>1073741824 #GBytes
        val = (((inbound/1073741824.0)*100).round/100.0).to_s + "G"
      when inbound>1048576 #MBytes
        val = (((inbound/1048576.0)*100).round/100.0).to_s + "M"
      when inbound>1024
        val = (((inbound/1024.0)*100).round/100.0).to_s + "K"
      else
        val = ((inbound*100).round/100.0).to_s + "B"
    end
    val
  end
  
  def outbound_readable
    case
      when outbound>1073741824 #GBytes
        val = (((outbound/1073741824.0)*100).round/100.0).to_s + "G"
      when outbound>1048576 #MBytes
        val = (((outbound/1048576.0)*100).round/100.0).to_s + "M"
      when outbound>1024
        val = (((outbound/1024.0)*100).round/100.0).to_s + "K"
      else
        val = ((outbound*100).round/100.0).to_s + "B"
      end
    val
  end

  def total_readable
    case
      when total>1073741824 #GBytes
        val = (((total/1073741824.0)*100).round/100.0).to_s + "G"
      when outbound>1048576 #MBytes
        val = (((total/1048576.0)*100).round/100.0).to_s + "M"
      when outbound>1024
        val = (((total/1024.0)*100).round/100.0).to_s + "K"
      else
        val = ((total*100).round/100.0).to_s + "B"
      end
    val
  end

end

def generate_report(host,interfaces,date,daterange,email_to)

  startdate_s = (date+daterange).strftime('%Y%m%d')
  enddate_s = date.strftime('%Y%m%d')

  getreport(host,date.to_s,daterange,interfaces)

  puts Temp_Totals.report_table(:all, :only => [:interface], :methods => [:inbound_readable,:outbound_readable,:total_readable]) if $debug

  email = TMail::Mail.new
  email.to=email_to
  email.from='root@lisa.netrique.net'
  email.subject="Bandwidth Report #{startdate_s}-#{enddate_s}"
  email.mime_version='1.0'
  email.set_content_type("multipart","mixed")

  mailpart1 = TMail::Mail.new
  mailpart1.body= <<EOM
Bandwidth Report External Procurve
#{(date-7).to_s} 00:00hrs - #{date.to_s} 00:00hrs

#{Temp_Totals.report_table(:all, :only => [:interface], :methods => [:inbound_readable,:outbound_readable,:total_readable])}

Totals are cumulative in bytes.
EOM
  mailpart1.set_content_type("text","plain")

  email.parts.push(mailpart1)

  mailpart2 = TMail::Mail.new
  mailpart2.body=Base64.encode64(Temp_Totals.report_table.to_csv)
  mailpart2.transfer_encoding="Base64"
  mailpart2.set_content_type("text","plain")
  mailpart2['Content-Disposition'] = "inline;
   filename=bandwidth-#{enddate_s}.csv"

  email.parts.push(mailpart2)

  puts email.to_s if $debug

  Net::SMTP::start('localhost') do |smtp|
    smtp.send_message(email.to_s,email.from,email.to)
	end

end

#Variables that hold what we're doing.

#What is the Zabbix Hostname of the switch we want to use?
host = 'External Procurve'

#array of base interface names.  Script expects interfaces to follow the 
#following format within Zabbix.
#if(In,Out)Octets(00-99)
interfaces = ["if_01","if_02","if_03","if_04","if_05","if_06","if_07","if_08"]

#What is the last day for reporting
date = Date.today
#date = Date::civil(2009,1,18)

#How many days previous or after the date should this report cover?
daterange = -7

#Who are we sending this report to?
email_to= ['someone','another_person']
#If you wish to change the "from" email address it can be found in the above
#function under the variable email.from

#ok, let's do it!
generate_report(host,interfaces,date,daterange,email_to)
