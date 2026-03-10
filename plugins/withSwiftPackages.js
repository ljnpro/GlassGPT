const { withXcodeProject } = require("@expo/config-plugins");

/**
 * Expo config plugin to add Swift Package Manager dependencies
 * to the Xcode project for native SwiftUI code.
 *
 * These packages are used by the NativeChatApp Swift code:
 * - MarkdownUI: Markdown rendering in SwiftUI
 * - Highlightr: Syntax highlighting for code blocks
 * - LaTeXSwiftUI: LaTeX math rendering
 */
const withSwiftPackages = (config) => {
  return withXcodeProject(config, async (config) => {
    const project = config.modResults;

    // Get the project object
    const projectObj = project.getFirstProject().firstProject;
    const mainGroupId = projectObj.mainGroup;

    // Add Swift Package references
    const packages = [
      {
        name: "swift-markdown-ui",
        url: "https://github.com/gonzalezreal/swift-markdown-ui.git",
        requirement: {
          kind: "upToNextMajorVersion",
          minimumVersion: "2.4.0",
        },
        productName: "MarkdownUI",
      },
      {
        name: "Highlightr",
        url: "https://github.com/raspu/Highlightr.git",
        requirement: {
          kind: "upToNextMajorVersion",
          minimumVersion: "2.3.0",
        },
        productName: "Highlightr",
      },
      {
        name: "LaTeXSwiftUI",
        url: "https://github.com/colinc86/LaTeXSwiftUI.git",
        requirement: {
          kind: "upToNextMajorVersion",
          minimumVersion: "1.3.0",
        },
        productName: "LaTeXSwiftUI",
      },
    ];

    // Initialize packageReferences array if not present
    if (!projectObj.packageReferences) {
      projectObj.packageReferences = [];
    }

    for (const pkg of packages) {
      // Create XCRemoteSwiftPackageReference
      const packageRefUuid = project.generateUuid();
      const packageRef = {
        isa: "XCRemoteSwiftPackageReference",
        repositoryURL: `"${pkg.url}"`,
        requirement: {
          kind: pkg.requirement.kind,
          minimumVersion: pkg.requirement.minimumVersion,
        },
      };

      project.hash.project.objects["XCRemoteSwiftPackageReference"] =
        project.hash.project.objects["XCRemoteSwiftPackageReference"] || {};
      project.hash.project.objects["XCRemoteSwiftPackageReference"][
        packageRefUuid
      ] = packageRef;
      project.hash.project.objects["XCRemoteSwiftPackageReference"][
        `${packageRefUuid}_comment`
      ] = pkg.name;

      // Add to project's packageReferences
      projectObj.packageReferences.push({
        value: packageRefUuid,
        comment: pkg.name,
      });

      // Create XCSwiftPackageProductDependency for the main target
      const productDepUuid = project.generateUuid();
      const productDep = {
        isa: "XCSwiftPackageProductDependency",
        package: packageRefUuid,
        productName: pkg.productName,
      };

      project.hash.project.objects["XCSwiftPackageProductDependency"] =
        project.hash.project.objects["XCSwiftPackageProductDependency"] || {};
      project.hash.project.objects["XCSwiftPackageProductDependency"][
        productDepUuid
      ] = productDep;
      project.hash.project.objects["XCSwiftPackageProductDependency"][
        `${productDepUuid}_comment`
      ] = pkg.productName;

      // Add product dependency to the main target's packageProductDependencies
      const targets = project.hash.project.objects["PBXNativeTarget"];
      for (const key in targets) {
        if (key.endsWith("_comment")) continue;
        const target = targets[key];
        if (target.name === '"LiquidGlassChat"' || target.name === "LiquidGlassChat") {
          if (!target.packageProductDependencies) {
            target.packageProductDependencies = [];
          }
          target.packageProductDependencies.push({
            value: productDepUuid,
            comment: pkg.productName,
          });
          break;
        }
      }
    }

    return config;
  });
};

module.exports = withSwiftPackages;
