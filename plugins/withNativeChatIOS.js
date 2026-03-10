const { withInfoPlist, withPodfileProperties } = require("@expo/config-plugins");

const withNativeChatIOS = (config) => {
  // Set iOS deployment target to 26.0 for liquid glass support
  config = withPodfileProperties(config, (config) => {
    config.modResults["ios.deploymentTarget"] = "26.0";
    return config;
  });

  // Add required permissions
  config = withInfoPlist(config, (config) => {
    config.modResults.NSPhotoLibraryUsageDescription =
      "Allow $(PRODUCT_NAME) to access your photo library so you can attach images to chats.";
    return config;
  });

  return config;
};

module.exports = withNativeChatIOS;
