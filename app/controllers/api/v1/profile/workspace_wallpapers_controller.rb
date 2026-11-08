class Api::V1::Profile::WorkspaceWallpapersController < Api::BaseController
  ALLOWED_CONTENT_TYPES = %w[image/jpeg image/png image/webp].freeze
  MAX_FILE_SIZE = 10.megabytes
  CARD_OPACITY_KEY = 'workspace_card_opacity'.freeze
  CARD_IDS = %w[crm oa hr orders erp team tiktok docs calendar].freeze

  def show
    attachment = current_user.workspace_wallpaper
    render json: { url: attachment.attached? ? rails_blob_path(attachment, only_path: true) : nil, card_opacity: current_card_opacity }
  end

  def update
    settings = workspace_settings_params
    return unless settings

    save_workspace_settings(**settings)
    show
  end

  def destroy
    save_workspace_settings(remove_wallpaper: true)
    show
  end

  private

  def workspace_settings_params
    wallpaper = wallpaper_attributes
    remove_wallpaper = remove_wallpaper?
    opacity = card_opacity_params if params.key?(:card_opacity)
    raise ArgumentError, 'Choose an image or remove the wallpaper, not both.' if wallpaper && remove_wallpaper

    { wallpaper: wallpaper, remove_wallpaper: remove_wallpaper, opacity: opacity }
  rescue ArgumentError => e
    render json: { error: e.message }, status: :unprocessable_entity
    nil
  end

  def wallpaper_attributes
    return unless params.key?(:wallpaper)

    file = params.permit(:wallpaper)[:wallpaper]
    unless file.is_a?(ActionDispatch::Http::UploadedFile) && file.size.positive? && file.size <= MAX_FILE_SIZE
      raise ArgumentError, 'Choose an image up to 10 MB.'
    end

    content_type = Marcel::MimeType.for(file.tempfile)
    raise ArgumentError, 'Choose a JPG, PNG or WebP image.' unless ALLOWED_CONTENT_TYPES.include?(content_type)

    file.tempfile.rewind
    { io: file.tempfile, filename: file.original_filename, content_type: content_type }
  end

  def remove_wallpaper?
    return false unless params.key?(:remove_wallpaper)

    value = params.permit(:remove_wallpaper)[:remove_wallpaper]
    return true if value == true || value == 'true'
    return false if value == false || value == 'false'

    raise ArgumentError, 'remove_wallpaper must be true or false.'
  end

  def current_card_opacity
    current_user.ui_settings&.fetch(CARD_OPACITY_KEY, nil) || { 'all' => 100, 'overrides' => {} }
  end

  def card_opacity_params
    opacity = params[:card_opacity]
    unless opacity.is_a?(ActionController::Parameters) && (opacity.keys - %w[all overrides]).empty?
      raise ArgumentError, 'card_opacity must contain only all and overrides.'
    end

    if opacity.key?(:overrides)
      overrides = opacity[:overrides]
      unless overrides.is_a?(ActionController::Parameters) && (overrides.keys - CARD_IDS).empty?
        raise ArgumentError, 'card_opacity overrides must contain only supported card IDs.'
      end
    end

    permitted = opacity.permit(:all, overrides: CARD_IDS).to_h
    permitted['all'] = opacity_integer(opacity[:all]) if opacity.key?(:all)
    permitted['overrides'] = overrides.keys.to_h { |id| [id, opacity_integer(overrides[id])] } if overrides
    permitted['overrides'] ||= {} if opacity.key?(:all)
    permitted
  end

  def opacity_integer(value)
    valid_type = value.is_a?(Integer) || (value.is_a?(String) && /\A(?:0|[1-9][0-9]{0,2})\z/.match?(value))
    return value.to_i if valid_type && value.to_i.between?(0, 100)

    raise ArgumentError, 'Card opacity must be an integer from 0 to 100.'
  end

  def save_workspace_settings(wallpaper: nil, remove_wallpaper: false, opacity: nil)
    current_user.with_lock do
      current_user.workspace_wallpaper = wallpaper if wallpaper
      current_user.workspace_wallpaper = nil if remove_wallpaper
      if opacity
        settings = current_card_opacity.merge(opacity)
        current_user.ui_settings = (current_user.ui_settings || {}).merge(CARD_OPACITY_KEY => settings)
      end
      current_user.save!
    end
  end
end
