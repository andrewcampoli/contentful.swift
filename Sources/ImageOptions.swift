//
//  Image.swift
//  Contentful
//
//  Created by JP Wright on 24.05.17.
//  Copyright © 2017 Contentful GmbH. All rights reserved.
//

import Foundation
import CoreGraphics

extension Asset {

    /**
     The URL for the underlying media file with additional options for server side manipulations
     such as format changes, resizing, cropping, and focusing on different areas including on faces,
     among others.

     - Parameter imageOptions: An array of `ImageOption` that will be used for server side manipulations.
     - Throws: Will throw SDKError if the SDK is unable to generate a valid URL with the desired ImageOptions.
     */
    public func url(with imageOptions: [ImageOption] = []) throws -> URL {

        // Check that there are no two image options that specifiy the same query parameter.
        // https://stackoverflow.com/a/27624476/4068264z
        // A Set is a collection of unique elements, so constructing them will invoke the Equatable implementation
        // and unique'ify the elements in the array.
        let uniqueImageOptions = Array(Set<ImageOption>(imageOptions))
        guard uniqueImageOptions.count == imageOptions.count else {
            throw SDKError.invalidImageParameters("Cannot specify two instances of ImageOption of the same case."
                + "i.e. `[.formatAs(.png), .formatAs(.jpg(withQuality: .unspecified)]` is invalid.")
        }
        guard imageOptions.count > 0 else {
            return try url()
        }

        let urlString = try url().absoluteString
        guard var urlComponents = URLComponents(string: urlString) else {
            throw SDKError.invalidURL(string: urlString)
        }

        urlComponents.queryItems = try imageOptions.flatMap { option in
            try option.urlQueryItems()
        }

        guard let url = urlComponents.url else {
            throw SDKError.invalidURL(string: urlString)
        }
        return url
    }
}


public enum ImageOption: Equatable, Hashable {

    /// Specify the size of the image in pixels to be returned from the API. Valid ranges for width and height are between 0 and 4000.
    case sizedTo(width: Int, height: Int)

    /// Specify the desired image filetype extension to be returned from the API.
    case formatAs(Format)

    /// Specify options for resizing behavior including . See `Fit` for available options.
    case fit(for: Fit)

    /// Specify the radius for rounded corners for an image.
    case withCornerRadius(Float)

    internal func urlQueryItems() throws -> [URLQueryItem] {
        switch self {
        case .sizedTo(let width, let height) where width > 0 && width <= 4000 && height > 0 && width <= 4000:
            let widthQueryItem = URLQueryItem(name: ImageParameters.width, value: String(width))
            let heightQueryItem = URLQueryItem(name: ImageParameters.height, value: String(height))

            return [widthQueryItem, heightQueryItem]
        case .sizedTo:
            throw SDKError.invalidImageParameters("The specified width and height are not within the acceptable range")
        case .formatAs(let format):
            return try format.urlQueryItems()

        case .fit(let fit):
            return try fit.urlQueryItems()

        case .withCornerRadius(let radius):
            return [URLQueryItem(name: ImageParameters.radius, value: String(radius))]
        }
    }

    // MARK: <Hashable>

    // Used to unique'ify an Array of ImageOption instances by converting to a Set.
    public var hashValue: Int {
        switch self {
        case .sizedTo:              return 0
        case .formatAs:          return 1
        case .fit:                  return 2
        case .withCornerRadius:     return 3
        }
    }
}

// MARK: <Equatable>

public func == (lhs: ImageOption, rhs: ImageOption) -> Bool {
    // We don't need to check associated values, we only implement equatable to validate that
    // two ImageOptions of the same case can't be used in one request.
    switch (lhs, rhs) {
    case (.sizedTo, .sizedTo):
        return true
    case (.formatAs, .formatAs):
        return true
    case (.fit, .fit):
        return true
    case (.withCornerRadius, .withCornerRadius):
        return true
    default:
        return false
    }
}

/**
 Quality options for JPG images to be used when specifying jpg as the desired image format.
 Example usage
 
 ```
 let imageOptions = [.formatAs(.jpg(withQuality: .asPercent(50)))]
 ```
 */
public enum JPGQuality {

    /// Don't specify any quality for the JPG image.
    case unspecified

    /// Specify the JPG quality as a percentage. Valid ranges are 0-100 (inclusive).
    case asPercent(UInt)

    /// Specify that the API should return a progressive JPG.
    /// The progressive JPEG format stores multiple passes of an image in progressively higher detail.
    case progressive

    fileprivate func urlQueryItem() throws -> URLQueryItem? {
        switch self {
        case .unspecified:
            return nil
        case .asPercent(let quality):
            if quality > 100 {
                throw SDKError.invalidImageParameters("JPG quality must be between 0 and 100 (inclusive).")
            }
            return URLQueryItem(name: ImageParameters.quality, value: String(quality))
        case .progressive:
            return URLQueryItem(name: ImageParameters.progressiveJPG, value: "progressive")
        }
    }
}


/**
 Use `Format` to specify the image file formats supported by Contentful's Images API.
 Supported formats are `jpg` `png` and `webp`.
 */
public enum Format: URLImageQueryExtendable {

    internal var imageQueryParameter: String {
        return ImageParameters.format
    }

    /// Specify that the API should return the image as a jpg. Additionally, you can choose to specify
    /// a quality, or you can choose `jpg(withQuality: .unspecified).
    case jpg(withQuality: JPGQuality)

    /// Specify that the API should return the image as a png.
    case png

    /// Specify that the API should return the image as a webp file.
    case webp

    fileprivate func urlArgument() -> String {
        switch  self {
        case .jpg:          return "jpg"
        case .png:          return "png"
        case .webp:         return "webp"
        }
    }

    fileprivate func additionalQueryItem() throws -> URLQueryItem? {
        switch self {
        case .jpg(let quality):
            return try quality.urlQueryItem()
        default:
            return nil
        }
    }
}

/**
 Use `Focus` to specify the focus area when resizing an image using either the `Fit.thumb`, `Fit.fill`
 and `Fit.crop` options.
 See [Contentful's Images API Reference Docs](https://www.contentful.com/developers/docs/references/images-api/#/reference/resizing-&-cropping/specify-focus-area-for-resizing)
 for more information.
 */
public enum Focus: String {
    case top
    case bottom
    case left
    case right
    case topLeft            = "top_left"
    case topRight           = "top_right"
    case bottomLeft         = "bottom_left"
    case bottomRight        = "bottom_right"
    case face
    case faces
}

/**
 The various options available within Fit specify different resizing behaviors for use in 
 conjunction with the `ImageOption.fit(for: Fit)` option. By default, images are resized to fit 
 inside the bounding box given by `w and `h while retaining their aspect ratio.
 Using the `Fit` options, you can change this behavior.
 */
public enum Fit: URLImageQueryExtendable {

    case pad(withBackgroundColor: CGColor?)
    case crop(focusingOn: Focus?)
    case fill(focusingOn: Focus?)
    case thumb(focusingOn: Focus?)
    case scale

    // Enums that have cases with associated values in swift can't be backed by
    // String so we must reimplement returning the raw case value.
    fileprivate func urlArgument() -> String {
        switch self {
        case .pad:          return "pad"
        case .crop:         return "crop"
        case .fill:         return "fill"
        case .thumb:        return "thumb"
        case .scale:        return "scale"
        }
    }

    fileprivate var imageQueryParameter: String {
        return ImageParameters.fit
    }

    fileprivate func additionalQueryItem() -> URLQueryItem? {
        switch self {
        case .pad(let .some(color)):
            return URLQueryItem(name: ImageParameters.backgroundColor, value: color.hexRepresentation())

        case .thumb(let .some(focus)):
            return URLQueryItem(name: ImageParameters.focus, value: focus.rawValue)

        case .fill(let .some(focus)):
            return URLQueryItem(name: ImageParameters.focus, value: focus.rawValue)

        case .crop(let .some(focus)):
            return URLQueryItem(name: ImageParameters.focus, value: focus.rawValue)

        default:
            return nil
        }
    }
}


// MARK: - Private

fileprivate protocol URLImageQueryExtendable {

    var imageQueryParameter: String { get }

    func additionalQueryItem() throws -> URLQueryItem?

    func urlArgument() -> String
}

fileprivate extension URLImageQueryExtendable {

    fileprivate func urlQueryItems() throws -> [URLQueryItem] {
        var urlQueryItems = [URLQueryItem]()

        let firstItem = URLQueryItem(name: imageQueryParameter, value: urlArgument())
        urlQueryItems.append(firstItem)

        if let item = try additionalQueryItem() {
            urlQueryItems.append(item)
        }

        return urlQueryItems
    }
}

fileprivate struct ImageParameters {

    static let width            = "w"
    static let height           = "h"
    static let radius           = "r"
    static let focus            = "f"
    static let backgroundColor  = "bg"
    static let fit              = "fit"
    static let format           = "fm"
    static let quality          = "q"
    static let progressiveJPG   = "fl"
}

// Use CGColor instead of UIColor to enable cross-platform compatibility: macOS, iOS, tvOS, watchOS.
internal extension CGColor {

    // If for some reason the following code fails to create a hex string, the color black will be
    // returned.
    internal func hexRepresentation() -> String {
        let hexForBlack = "ffffff"
        guard let colorComponents = components else { return hexForBlack }
        guard let colorSpace = colorSpace else { return hexForBlack }

        let r, g, b: Float

        switch colorSpace.model {
        case .monochrome:
            r = Float(colorComponents[0])
            g = Float(colorComponents[0])
            b = Float(colorComponents[0])

        case .rgb:
            r = Float(colorComponents[0])
            g = Float(colorComponents[1])
            b = Float(colorComponents[2])
        default:
            return hexForBlack
        }

        // Search the web for Swift UIColor to hex.
        // This answer helped: https://stackoverflow.com/a/30967091/4068264
        let hexString = String(format: "%02lX%02lX%02lX", lroundf(r * 255), lroundf(g * 255), lroundf(b * 255))
        return hexString
    }
}
