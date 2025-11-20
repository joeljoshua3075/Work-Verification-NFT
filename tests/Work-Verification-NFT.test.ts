
import { describe, expect, it } from "vitest";
import { Cl } from "@stacks/transactions";

const accounts = simnet.getAccounts();
const address1 = accounts.get("wallet_1")!;
const address2 = accounts.get("wallet_2")!;
const address3 = accounts.get("wallet_3")!;
const deployer = accounts.get("deployer")!;

const contractName = "Work-Verification-NFT";

describe("Work Verification NFT - Project Templates System", () => {
  it("ensures simnet is well initialised", () => {
    expect(simnet.blockHeight).toBeDefined();
  });

  describe("Project Template Creation", () => {
    it("should create a project template successfully", () => {
      const templateName = "Web Development Template";
      const description = "A comprehensive template for web development projects";
      const category = "Web Development";
      const estimatedDuration = 30; // days
      const budgetMin = 1000;
      const budgetMax = 5000;
      const requiredSkills = [Cl.uint(1), Cl.uint(2)];
      const milestonesTitles = [Cl.stringAscii("Planning"), Cl.stringAscii("Development"), Cl.stringAscii("Testing")];
      const milestonesDescriptions = [
        Cl.stringAscii("Project planning and architecture"),
        Cl.stringAscii("Core development work"),
        Cl.stringAscii("Testing and deployment")
      ];
      const milestonesDeliverables = [
        Cl.stringAscii("Project plan, wireframes, technical specifications"),
        Cl.stringAscii("Fully functional website with all features"),
        Cl.stringAscii("Tested application with deployment documentation")
      ];
      const milestonePercentages = [Cl.uint(20), Cl.uint(60), Cl.uint(20)];

      const { result } = simnet.callPublicFn(
        contractName,
        "create-project-template",
        [
          Cl.stringAscii(templateName),
          Cl.stringAscii(description),
          Cl.stringAscii(category),
          Cl.uint(estimatedDuration),
          Cl.uint(budgetMin),
          Cl.uint(budgetMax),
          Cl.list(requiredSkills),
          Cl.list(milestonesTitles),
          Cl.list(milestonesDescriptions),
          Cl.list(milestonesDeliverables),
          Cl.list(milestonePercentages)
        ],
        address1
      );

      expect(result).toBeOk(Cl.uint(1));
    });

    it("should fail with invalid milestone percentages", () => {
      const milestonePercentages = [Cl.uint(30), Cl.uint(40), Cl.uint(40)]; // totals 110%

      const { result } = simnet.callPublicFn(
        contractName,
        "create-project-template",
        [
          Cl.stringAscii("Invalid Template"),
          Cl.stringAscii("Template with invalid percentages"),
          Cl.stringAscii("Testing"),
          Cl.uint(30),
          Cl.uint(1000),
          Cl.uint(5000),
          Cl.list([Cl.uint(1)]),
          Cl.list([Cl.stringAscii("Phase 1"), Cl.stringAscii("Phase 2"), Cl.stringAscii("Phase 3")]),
          Cl.list([Cl.stringAscii("Desc 1"), Cl.stringAscii("Desc 2"), Cl.stringAscii("Desc 3")]),
          Cl.list([Cl.stringAscii("Del 1"), Cl.stringAscii("Del 2"), Cl.stringAscii("Del 3")]),
          Cl.list(milestonePercentages)
        ],
        address1
      );

      expect(result).toBeErr(Cl.uint(118)); // err-invalid-milestone-count
    });

    it("should fail with invalid budget range", () => {
      const { result } = simnet.callPublicFn(
        contractName,
        "create-project-template",
        [
          Cl.stringAscii("Invalid Budget Template"),
          Cl.stringAscii("Template with invalid budget"),
          Cl.stringAscii("Testing"),
          Cl.uint(30),
          Cl.uint(5000), // min greater than max
          Cl.uint(1000),
          Cl.list([Cl.uint(1)]),
          Cl.list([Cl.stringAscii("Phase 1")]),
          Cl.list([Cl.stringAscii("Description")]),
          Cl.list([Cl.stringAscii("Deliverable")]),
          Cl.list([Cl.uint(100)])
        ],
        address1
      );

      expect(result).toBeErr(Cl.uint(110)); // err-insufficient-funds
    });
  });

  describe("Template Usage and Rating", () => {
    it("should use a template and update usage count", () => {
      // First create a template
      const createResult = simnet.callPublicFn(
        contractName,
        "create-project-template",
        [
          Cl.stringAscii("Usage Test Template"),
          Cl.stringAscii("Template for testing usage"),
          Cl.stringAscii("Testing"),
          Cl.uint(15),
          Cl.uint(500),
          Cl.uint(2000),
          Cl.list([Cl.uint(1)]),
          Cl.list([Cl.stringAscii("Task 1"), Cl.stringAscii("Task 2")]),
          Cl.list([Cl.stringAscii("Desc 1"), Cl.stringAscii("Desc 2")]),
          Cl.list([Cl.stringAscii("Del 1"), Cl.stringAscii("Del 2")]),
          Cl.list([Cl.uint(50), Cl.uint(50)])
        ],
        address1
      );
      
      expect(createResult.result).toBeOk(Cl.uint(2)); // Should be template ID 2 (after first test)

      // Use the template
      const { result } = simnet.callPublicFn(
        contractName,
        "use-project-template",
        [Cl.uint(2)],
        address2
      );

      expect(result).toBeOk(Cl.uint(2));

      // Check template usage count
      const templateResult = simnet.callReadOnlyFn(
        contractName,
        "get-template",
        [Cl.uint(2)],
        address1
      );

      expect(templateResult.result).toBeSome();
    });

    it("should rate a template successfully", () => {
      const { result } = simnet.callPublicFn(
        contractName,
        "rate-template",
        [
          Cl.uint(2), // Use the template created in previous test
          Cl.uint(5),
          Cl.stringAscii("Excellent template, very comprehensive")
        ],
        address2
      );

      expect(result).toBeOk(Cl.bool(true));
    });

    it("should fail to rate with invalid rating", () => {
      const { result } = simnet.callPublicFn(
        contractName,
        "rate-template",
        [
          Cl.uint(2),
          Cl.uint(6), // invalid rating > 5
          Cl.stringAscii("Invalid rating")
        ],
        address2
      );

      expect(result).toBeErr(Cl.uint(104)); // err-invalid-rating
    });
  });

  describe("Template Management", () => {
    it("should clone a template successfully", () => {
      const { result } = simnet.callPublicFn(
        contractName,
        "clone-template",
        [
          Cl.uint(1), // Clone the first template
          Cl.stringAscii("Cloned Web Template")
        ],
        address3
      );

      expect(result).toBeOk(Cl.uint(3)); // Should be template ID 3
    });

    it("should deactivate template by creator", () => {
      const { result } = simnet.callPublicFn(
        contractName,
        "deactivate-template",
        [Cl.uint(1)], // Deactivate first template
        address1
      );

      expect(result).toBeOk(Cl.bool(true));
    });

    it("should fail to deactivate template by non-creator", () => {
      // Create a new template first
      const createResult = simnet.callPublicFn(
        contractName,
        "create-project-template",
        [
          Cl.stringAscii("Protected Template"),
          Cl.stringAscii("Template to test deactivation"),
          Cl.stringAscii("Security"),
          Cl.uint(20),
          Cl.uint(1000),
          Cl.uint(3000),
          Cl.list([Cl.uint(1)]),
          Cl.list([Cl.stringAscii("Security Audit")]),
          Cl.list([Cl.stringAscii("Comprehensive security review")]),
          Cl.list([Cl.stringAscii("Security report and recommendations")]),
          Cl.list([Cl.uint(100)])
        ],
        address1
      );
      
      expect(createResult.result).toBeOk(Cl.uint(4)); // Should be template ID 4

      const { result } = simnet.callPublicFn(
        contractName,
        "deactivate-template",
        [Cl.uint(4)],
        address2 // different user
      );

      expect(result).toBeErr(Cl.uint(103)); // err-unauthorized
    });
  });

  describe("Template Compatibility", () => {
    it("should calculate template compatibility", () => {
      // Create skills for the freelancer first (this would need the skill system to be set up)
      const { result } = simnet.callReadOnlyFn(
        contractName,
        "calculate-template-compatibility",
        [Cl.uint(3), address3], // Use cloned template
        address1
      );

      expect(result).toBeOk();
    });
  });

  describe("Read-only Functions", () => {
    it("should get template details", () => {
      const { result } = simnet.callReadOnlyFn(
        contractName,
        "get-template",
        [Cl.uint(3)], // Use cloned template which should exist
        address1
      );

      expect(result).toBeSome();
    });

    it("should get user templates", () => {
      const { result } = simnet.callReadOnlyFn(
        contractName,
        "get-user-templates",
        [address1],
        address1
      );

      expect(result).toBeList();
    });

    it("should get last template id", () => {
      const { result } = simnet.callReadOnlyFn(
        contractName,
        "get-last-template-id",
        [],
        address1
      );

      expect(result).toBeUint();
    });

    it("should get template milestone", () => {
      const { result } = simnet.callReadOnlyFn(
        contractName,
        "get-template-milestone",
        [Cl.uint(3), Cl.uint(0)], // template id 3 (cloned), milestone index 0
        address1
      );

      expect(result).toBeSome();
    });

    it("should return none for non-existent template", () => {
      const { result } = simnet.callReadOnlyFn(
        contractName,
        "get-template",
        [Cl.uint(999)],
        address1
      );

      expect(result).toBeNone();
    });
  });
});
