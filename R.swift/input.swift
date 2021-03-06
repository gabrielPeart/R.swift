//
//  input.swift
//  R.swift
//
//  Created by Mathijs Kadijk on 03-09-15.
//  From: https://github.com/mac-cain13/R.swift
//  License: MIT License
//

import Foundation

enum InputParsingError: ErrorType {
  case IllegalOption(error: String, helpString: String)
  case MissingOption(error: String, helpString: String)
  case UserAskedForHelp(helpString: String)
}

private let xcodeprojOption = Option(
  trigger: .Mixed("p", "xcodeproj"),
  numberOfParameters: 1,
  helpDescription: "Path to the xcodeproj file, if non given R.swift will use the environment variable PROJECT_FILE_PATH."
)
private let targetOption = Option(
  trigger: .Mixed("t", "target"),
  numberOfParameters: 1,
  helpDescription: "Target the R-file should be generated for, if none given R.swift will use the environment variable TARGET_NAME."
)
private let bundleIdentifierOption = Option(
  trigger: .Long("bundleIdentifier"),
  numberOfParameters: 1,
  helpDescription: "Bundle identifier the R-file is be generated for, if none given R.swift will use the environment variable PRODUCT_BUNDLE_IDENTIFIER."
)
private let productModuleNameOption = Option(
  trigger: .Long("productModuleName"),
  numberOfParameters: 1,
  helpDescription: "Product module name the R-file is generated for, is none given R.swift will use the environment variable PRODUCT_MODULE_NAME"
)
private let buildProductsDirOption = Option(
  trigger: .Long("buildProductsDir"), 
  numberOfParameters: 1, 
  helpDescription: "Build products folder that Xcode uses during build, if none given R.swift will use the environment variable BUILT_PRODUCTS_DIR."
)
private let developerDirOption = Option(
  trigger: .Long("developerDir"), 
  numberOfParameters: 1, 
  helpDescription: "Developer folder that Xcode uses during build, if none given R.swift will use the environment variable DEVELOPER_DIR."
)
private let sourceRootOption = Option(
  trigger: .Long("sourceRoot"), 
  numberOfParameters: 1, 
  helpDescription: "Source root folder that Xcode uses during build, if none given R.swift will use the environment variable SOURCE_ROOT."
)
private let sdkRootOption = Option(
  trigger: .Long("sdkRoot"), 
  numberOfParameters: 1, 
  helpDescription: "SDK root folder that Xcode uses during build, if none given R.swift will use the environment variable SDKROOT."
)

private let AllOptions = [
  xcodeprojOption,
  targetOption,
  bundleIdentifierOption,
  buildProductsDirOption,
  developerDirOption,
  sourceRootOption,
  sdkRootOption,
  productModuleNameOption,
]

struct CallInformation {
  let outputURL: NSURL

  let xcodeprojURL: NSURL
  let targetName: String
  let bundleIdentifier: String
  let productModuleName: String

  private let buildProductsDirURL: NSURL
  private let developerDirURL: NSURL
  private let sourceRootURL: NSURL
  private let sdkRootURL: NSURL

  init(processInfo: NSProcessInfo) throws {
    try self.init(arguments: processInfo.arguments, environment: processInfo.environment)
  }

  init(arguments: [String], environment: [String: String]) throws {
    let optionParser = OptionParser(definitions: AllOptions)
    let commandName = arguments.first.flatMap { NSURL(fileURLWithPath: $0).lastPathComponent } ?? "rswift"
    let argumentsWithoutCall = Array(arguments.dropFirst())

    do {
      let (options, extraArguments) = try optionParser.parse(argumentsWithoutCall)

      if options[optionParser.helpOption] != nil {
        throw InputParsingError.UserAskedForHelp(helpString: optionParser.helpStringForCommandName(commandName))
      }

      guard let outputPath = extraArguments.first where extraArguments.count == 1 else {
        throw InputParsingError.IllegalOption(
          error: "Output folder for the 'R.generated.swift' file is mandatory as last argument.",
          helpString: optionParser.helpStringForCommandName(commandName)
        )
      }

      let outputURL = NSURL(fileURLWithPath: outputPath)

      var resourceValue: AnyObject?
      try! outputURL.getResourceValue(&resourceValue, forKey: NSURLIsDirectoryKey)
      if let isDirectory = (resourceValue as? NSNumber)?.boolValue where isDirectory {
        self.outputURL = outputURL.URLByAppendingPathComponent(ResourceFilename, isDirectory: false)
      } else {
        self.outputURL = outputURL
      }

      let getFirstArgumentForOption = getFirstArgumentFromOptionData(options, helpString: optionParser.helpStringForCommandName(commandName))

      let xcodeprojPath = try getFirstArgumentForOption(xcodeprojOption, defaultValue: environment["PROJECT_FILE_PATH"])
      xcodeprojURL = NSURL(fileURLWithPath: xcodeprojPath)

      targetName = try getFirstArgumentForOption(targetOption, defaultValue: environment["TARGET_NAME"])

      bundleIdentifier = try getFirstArgumentForOption(bundleIdentifierOption, defaultValue: environment["PRODUCT_BUNDLE_IDENTIFIER"])

      productModuleName = try getFirstArgumentForOption(productModuleNameOption, defaultValue: environment["PRODUCT_MODULE_NAME"])

      let buildProductsDirPath = try getFirstArgumentForOption(buildProductsDirOption, defaultValue: environment["BUILT_PRODUCTS_DIR"])
      buildProductsDirURL = NSURL(fileURLWithPath: buildProductsDirPath)

      let developerDirPath = try getFirstArgumentForOption(developerDirOption, defaultValue: environment["DEVELOPER_DIR"])
      developerDirURL = NSURL(fileURLWithPath: developerDirPath)

      let sourceRootPath = try getFirstArgumentForOption(sourceRootOption, defaultValue: environment["SOURCE_ROOT"])
      sourceRootURL = NSURL(fileURLWithPath: sourceRootPath)

      let sdkRootPath = try getFirstArgumentForOption(sdkRootOption, defaultValue: environment["SDKROOT"])
      sdkRootURL = NSURL(fileURLWithPath: sdkRootPath)
    } catch let OptionKitError.InvalidOption(invalidOption) {
      throw InputParsingError.IllegalOption(
        error: "The option '\(invalidOption)' is invalid.",
        helpString: optionParser.helpStringForCommandName(commandName)
      )
    }
  }

  func URLForSourceTreeFolder(sourceTreeFolder: SourceTreeFolder) -> NSURL {
    switch sourceTreeFolder {
    case .BuildProductsDir:
      return buildProductsDirURL
    case .DeveloperDir:
      return developerDirURL
    case .SDKRoot:
      return sdkRootURL
    case .SourceRoot:
      return sourceRootURL
    }
  }
}

private func getFirstArgumentFromOptionData(options: [Option:[String]], helpString: String) -> (_: Option, defaultValue: String?) throws -> String {
    return { (option, defaultValue) in
        guard let result = options[option]?.first ?? defaultValue else {
            throw InputParsingError.MissingOption(error: "Missing option: \(option) ", helpString: helpString)
        }
        
        return result
    }
}

func pathResolverWithSourceTreeFolderToURLConverter(URLForSourceTreeFolder: SourceTreeFolder -> NSURL) -> (path: Path) -> NSURL {
    return { path in
        switch path {
        case let .Absolute(absolutePath):
            return NSURL(fileURLWithPath: absolutePath)
        case let .RelativeTo(sourceTreeFolder, relativePath):
            let sourceTreeURL = URLForSourceTreeFolder(sourceTreeFolder)
            return sourceTreeURL.URLByAppendingPathComponent(relativePath)
        }
    }
}
