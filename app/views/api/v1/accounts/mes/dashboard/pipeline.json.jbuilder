json.stages @stages do |stage|
  cards = @cards_by_stage[stage] || []
  json.stage stage
  json.label Mes::ProductionOrder::STAGE_LABELS[stage]
  json.count cards.size
  json.cards cards do |c|
    json.merge! c
  end
end
