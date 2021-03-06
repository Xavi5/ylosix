# == Schema Information
#
# Table name: products
#
#  barcode                        :string
#  control_stock                  :boolean          default(FALSE)
#  created_at                     :datetime
#  depth                          :decimal(10, 6)   default(0.0), not null
#  description_translations       :hstore           default({}), not null
#  enabled                        :boolean          default(FALSE)
#  features_translations          :hstore           default({}), not null
#  height                         :decimal(10, 6)   default(0.0), not null
#  href_translations              :hstore           default({}), not null
#  id                             :integer          not null, primary key
#  image_content_type             :string
#  image_file_name                :string
#  image_file_size                :integer
#  image_updated_at               :datetime
#  meta_tags_translations         :hstore           default({}), not null
#  name_translations              :hstore           default({}), not null
#  publication_date               :datetime         not null
#  reference_code                 :string
#  retail_price                   :decimal(10, 2)   default(0.0), not null
#  retail_price_pre_tax           :decimal(10, 5)   default(0.0), not null
#  short_description_translations :hstore           default({}), not null
#  show_action_name               :string
#  slug_translations              :hstore           default({}), not null
#  stock                          :integer          default(0)
#  tax_id                         :integer
#  unpublication_date             :datetime
#  updated_at                     :datetime
#  visible                        :boolean          default(TRUE)
#  weight                         :decimal(10, 6)   default(0.0), not null
#  width                          :decimal(10, 6)   default(0.0), not null
#
# Indexes
#
#  index_products_on_enabled  (enabled)
#  index_products_on_tax_id   (tax_id)
#  index_products_on_visible  (visible)
#
# Foreign Keys
#
#  fk_rails_f5661f270e  (tax_id => taxes.id)
#

class Product < ActiveRecord::Base
  has_paper_trail

  include InitializeSlug
  include ArrayLiquid
  include MetaTags

  IMAGE_SIZES = {thumbnail: 'x100', small: 'x300', medium: 'x500', original: 'x720'}

  translates :name, :short_description, :description, :features, :slug, :href, :meta_tags
  has_attached_file :image, styles: IMAGE_SIZES

  validates_attachment_size :image, less_than: 2.megabytes
  validates_attachment_content_type :image, content_type: %r{\Aimage/.*\Z}

  belongs_to :tax
  has_many :products_categories
  has_many :categories, through: :products_categories

  has_many :products_tags
  has_many :tags, through: :products_tags

  has_many :products_pictures
  has_many :shopping_carts_products

  accepts_nested_attributes_for :products_categories, allow_destroy: true
  accepts_nested_attributes_for :products_tags, allow_destroy: true
  accepts_nested_attributes_for :products_pictures, allow_destroy: true

  after_initialize :default_publication_date

  after_save :save_global_slug

  default_scope { includes(:products_pictures) }

  scope :search_by_text, lambda { |text|
    where(visible: true)
        .where('publication_date <= ?', DateTime.now)
        .where('unpublication_date is null or unpublication_date >= ?', DateTime.now)
        .where('LOWER(name_translations->?) LIKE LOWER(?)
                                      OR LOWER(description_translations->?) LIKE LOWER(?)',
               I18n.locale, "%#{text}%", I18n.locale, "%#{text}%").group('products.id')
  }

  ransacker :by_name, formatter: lambda { |search|
    ids = Product.where('LOWER(name_translations->?) LIKE LOWER(?)', I18n.locale, "%#{search}%").pluck(:id)
    ids.any? ? ids : nil
  } do |parent|
    parent.table[:id]
  end

  ransacker :by_categorization, formatter: lambda { |search|
    ids = Product.joins(:products_categories).where(products_categories: {category_id: search}).pluck(:id)
    ids.any? ? ids : nil
  } do |parent|
    parent.table[:id]
  end

  ransacker :by_tagging, formatter: lambda { |search|
    ids = Product.joins(:products_tags).where(products_tags: {tag_id: search}).pluck(:id)
    ids.any? ? ids : nil
  } do |parent|
    parent.table[:id]
  end

  def self.in_frontend(category, not_in_list = [])
    products = Product.joins(:products_categories)

    products = products.where('products.enabled = true and products.visible = true')
    products = products.where('products.id not in (?)', not_in_list) if not_in_list.any?
    products = products.where('publication_date <= ?', DateTime.now)
                   .where('unpublication_date is null or unpublication_date >= ?', DateTime.now)
                   .where(products_categories:
                              {category_id: category.me_and_children.map(&:id)},
                          visible: true)
                   .group('products.id')
                   .order('products.publication_date DESC')

    products
  end

  def clone
    product = dup
    # TODO: need to fix nested attributes.
    # product.products_tags = self.products_tags
    # product.products_categories = self.products_categories

    product
  end

  def retrieve_image(type = :original)
    image_src = 'http://placehold.it/650x500'

    # TODO add fixed sizes as small, large, original, etc.
    case type
      when :thumbnail
        image_src = 'http://placehold.it/130x100'
      when :small
        image_src = 'http://placehold.it/390x300'
      when :medium
        image_src = 'http://placehold.it/650x500'
    end

    image_src = image.url(type) if image?
    image_src
  end

  def to_liquid(options = {})
    s_short_description = ''
    s_short_description = short_description.html_safe unless short_description.blank?

    s_description = ''
    s_description = description.html_safe unless description.blank?

    liquid = {
        'name' => name,
        'short_description' => s_short_description,
        'description' => s_description,
        'retail_price' => retail_price,
        'href' => href,
        'publication_date' => I18n.l(publication_date, format: :default),
        'add_to_shopping_cart_path' => Routes.product_add_to_shopping_cart_path(self),
        'update_shopping_carts_path' => Routes.update_shopping_carts_path(self),
        'delete_from_shopping_cart_path' => Routes.product_delete_from_shopping_cart_path(self)
    }

    # TODO, remove array_features.
    liquid['features'] = array_features if options[:features]
    liquid['features_hash'] = hash_features if options[:features]
    liquid['tags'] = array_tags if options[:tags]
    append_images(liquid)
  end

  def array_tags
    array_tags = []

    if products_tags.any?
      products_tags.each do |p_tag|
        array_tags << p_tag.tag.name
      end
    end

    array_tags
  end

  def array_features
    array_features = []

    unless features.blank?
      features_json = JSON.parse(features.gsub('=>', ':'))
      features = Feature.where(id: features_json.keys)

      features.each do |f|
        array_features << {'id' => f.id, 'key' => f.name, 'value' => features_json[f.id.to_s]}
      end
    end

    array_features
  end

  def hash_features
    hash_features = {}

    unless features.blank?
      features_json = JSON.parse(features.gsub('=>', ':'))
      features = Feature.where(id: features_json.keys)

      features.each do |f|
        hash_features[f.name] = features_json[f.id.to_s] unless f.blank?
      end
    end

    hash_features
  end

  protected

  def append_images(hash)
    hash['image'] = image?

    IMAGE_SIZES.each do |size, _k|
      hash["image_#{size}_src"] = retrieve_image(size)
    end

    if products_pictures.any?
      hash['products_pictures'] = []

      products_pictures.each do |picture|
        hash['products_pictures'] << picture.append_images
      end
    end

    hash
  end

  def default_publication_date
    self.publication_date ||= DateTime.now
  end

  def save_global_slug
    save_slug(:name_translations, self)
  end
end
