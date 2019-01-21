describe ManageIQ::ApplianceConsole::Utilities do
  describe ".db_region" do
    it "parses the region from a single line" do
      expect_result_string("2")
      expect(described_class.db_region).to eq("2")
    end

    it "parses the region from multiple lines" do
      expect_result_string("** ManageIQ hammer-1, codename: Hammer\n1\n")
      expect(described_class.db_region).to eq("1")
    end

    def expect_result_string(string)
      result = double(:output => string, :failure? => false)
      expect(AwesomeSpawn).to receive(:run).and_return(result)
    end
  end
end
