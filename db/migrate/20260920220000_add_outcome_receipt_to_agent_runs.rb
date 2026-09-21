class AddOutcomeReceiptToAgentRuns < ActiveRecord::Migration[8.2]
  def change
    add_column :agent_runs, :outcome_receipt_id, :string
    add_index :agent_runs, :outcome_receipt_id, unique: true
    add_foreign_key :agent_runs, :agent_receipts, column: :outcome_receipt_id
  end
end
