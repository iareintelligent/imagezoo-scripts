require 'csv'
require 'rubygems'
require 'shopify_api'
require 'pry'


WATERMARK_URL = "http://watermarklibs.s3-website-us-east-1.amazonaws.com/"  
API_KEY = "5be1e793270a36242c1368d6de5c3a9d"
PASSWORD = "ddcafc1072286dfb03dba080f7f5083d"
SHOP_NAME = "imagezoo"
CYCLE = 0.5
shop_url = "https://#{API_KEY}:#{PASSWORD}@#{SHOP_NAME}.myshopify.com/admin"
ShopifyAPI::Base.site = shop_url

artists = Array.new
products = Array.new

ID_COL = 0
NAME_COL = 1
SUPPLIER_COL = 1
DATE_COL = 2
TITLE_COL = 3
TAG_COL = 5
WR_COL = 4
HR_COL = 1

COLLECTION_COL = 26

uploaded_prods = CSV.open("uploaded-products.csv", "ab")

def build_artist_hash(artists)
    csv_artists = CSV.read('iz-artists.csv')
    csv_artists.each do |row|
        artists << { row[ID_COL] => row[NAME_COL] }
    end
    return artists
end


def prod_already_uploaded(product_id)
    uploaded_products = CSV.read("uploaded-products.csv")
    id_list = Array.new
    uploaded_products.each do |row|
        id_list << row[0]
    end
    return id_list.index {|e| e.include? product_id} == nil ? false : true
end

def prod_not_in_aws(product_id)
    aws_products = CSV.read("all2.csv")
    id_list = Array.new
    aws_products.each do |row|
        id_list << row[0]
    end
    return id_list.index {|e| e.include? product_id} == nil ? true : false
end

def get_product_tags(tags_array, image_id, artist_name)
    tags_array << image_id
    tags_array << artist_name
    return tags_array.compact.join(",")
end

def get_img_details(image_id, starting_col)
    csv_deets = CSV.read("product-details.csv")
    deets_list = Array.new
    size_col = starting_col
    width_col = starting_col + 1
    height_col = starting_col + 2
    csv_deets.drop(1).each do |row|

        if row[width_col].to_i > 0
            dpi = (starting_col == HR_COL) ? 300 : 72
            width = row[width_col].to_i
            height = row[height_col].to_i
            in_width = (width/dpi).round(1)
            in_height = (height/dpi).round(0)
            dim_details = "| #{in_width}x#{in_height} in | #{dpi} dpi | #{width}x#{height} px"
        else 
            dim_details = "| .eps vector files are scalable to any printable size"
        end
        size = row[size_col]
        details = "#{size} #{dim_details}"
        matching_id = row[0][0...7]
        deets_list << [matching_id, details]
    end
    index = deets_list.index {|e| e[0].upcase.include? image_id }
    if index
        return deets_list[index][1]
    else
        return false
    end
end

def send_prods_to_shopify(artists, products)
    csv_products = CSV.read('iz-images.csv')
    csv_all = CSV.read('product-details.csv')
    valid_products = Array.new
    csv_all.each do |row|
        valid_products << row[0][0...7].upcase
    end

    product_count = csv_products.size

    start_time = Time.now
    products_remaining = product_count
    processing_average = Array.new

    csv_products.each do |row|
        if valid_products.include? row[ID_COL][0...7]
        # avoiding duplication of server work 
            
            if prod_already_uploaded(row[ID_COL]) || prod_not_in_aws(row[ID_COL])
                products_remaining -= 1
                puts products_remaining
                csv_skipped = CSV.open("skipped-uploads.csv", "ab") do |csv|
                    csv << [row[ID_COL]]
                    # binding.pry
                end
                next
            end

            # convert vendor initials to full name
            vendor_name = artist_id_to_name(artists, row[SUPPLIER_COL])
            tags = get_product_tags(row.drop(TAG_COL), row[ID_COL], vendor_name)

            # pausing to keep our shopify api_call bucket full
            stop_time = Time.now
            processing_duration = stop_time - start_time
            processing_average << processing_duration
            start_time = Time.now
            puts "The processing lasted #{processing_duration.to_i} seconds."
            puts "#{products_remaining} Remaining"
            # wait_time = (CYCLE - processing_duration).ceil
            wait_time = 0
            puts "We have to wait #{wait_time} seconds then we will resume."
            sleep wait_time if wait_time > 0
            
            
            # we know that this exists if we're here
            product_watermark = get_product_image(row[ID_COL])
            
            #find the place to replace the watermark address with the thumbnail address
            # m = Regexp.new('.*?(_)', Regexp::IGNORECASE)
            # product_thumbnail = "#{m.match(product_watermark)[0]}t.jpg"

            # p product_thumbnail

            wr_details = get_img_details(row[ID_COL], WR_COL)
            hr_details = get_img_details(row[ID_COL], HR_COL)
            if hr_details.include? ".eps"
                option1 = ".eps Vector Image"
            else 
                option1 = "Hi-Res .jpg"
            end
            puts "#{row[ID_COL]} #{hr_details} | #{wr_details}"


            product = ShopifyAPI::Product.new({
                handle: row[ID_COL], 
                title: row[TITLE_COL],
                vendor: vendor_name,
                product_type: "Image",
                sku: row[ID_COL],
                tags: tags,

                variants: [
                    {
                        option1: option1,
                        price: "2.00",
                        sku: "#{row[ID_COL]}-HR",
                        barcode: hr_details,
                        requires_shipping: false
                    },
                    {
                        option1: "Web-Res .jpg",
                        price: "1.00",
                        sku: "#{row[ID_COL]}-Web",
                        barcode: wr_details,
                        requires_shipping: false

                    }
                ],
                images: [
                    { 
                        src: product_watermark,
                        position: 1 
                    }
                ]
                
            })

            begin
                # product.save
                products_remaining -= 1

                CSV.open("uploaded-products.csv", "ab") do |csv|
                    csv << [row[ID_COL], row[TITLE_COL], "", vendor_name, "Image", tags, TRUE, "Title", option1, ""   , "", "", "", "#{row[ID_COL]}-HR" , 0, "", "", "deny", "manual", 2, "", FALSE, FALSE, hr_details, product_watermark, 1, row[TITLE_COL], false, row[ID_COL], row[TITLE_COL]]
                    csv << [row[ID_COL], "", "", "", "", "", "", "", "Web-Res .jpg", "", "", "", "", "#{row[ID_COL]}-Web", 0, "", "", "deny", "manual", 1, "", FALSE, FALSE, wr_details, "", "", "", "", "", ""]
                end
                rescue ActiveResource::ClientError, Errno::ENETDOWN, ActiveResource::TimeoutError, ActiveResource::ServerError => e
                sleep 5
                retry
                
            end
        end
    end
end

def artist_id_to_name(artists, id)
    if a = artists.find {|h| h.key? id } then
        return a[id]
    else
        puts "#{id} not found"
    end
end

def get_product_image(image_id)
    csv_products = CSV.open("all2.csv")
    products = Hash.new

    csv_products.each do |row|
        products.store(row[0], row[1])
    end
    url = "#{WATERMARK_URL}#{products.dig(image_id)}"
    # puts url
    return url
end

artists = build_artist_hash(artists)
send_prods_to_shopify(artists, products)
