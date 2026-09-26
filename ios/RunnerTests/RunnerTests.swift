import AVFoundation
import XCTest
@testable import Runner

class RunnerTests: XCTestCase {
  func testPcm16MonoPreservesSignAndFullScale() throws {
    let format = try XCTUnwrap(AVAudioFormat(
      standardFormatWithSampleRate: 16000,
      channels: 1
    ))
    let buffer = try XCTUnwrap(Pcm16PlaybackBuffer.make(
      data: Data([0x00, 0x80, 0xFF, 0xFF, 0x00, 0x00, 0xFF, 0x7F]),
      format: format
    ))
    let samples = try XCTUnwrap(buffer.floatChannelData)[0]

    XCTAssertEqual(buffer.frameLength, 4)
    XCTAssertEqual(samples[0], -1.0)
    XCTAssertEqual(samples[1], -1.0 / 32768.0)
    XCTAssertEqual(samples[2], 0.0)
    XCTAssertEqual(samples[3], 32767.0 / 32768.0)
  }

  func testPcm16StereoDeinterleavesWithoutSwappingChannels() throws {
    let format = try XCTUnwrap(AVAudioFormat(
      standardFormatWithSampleRate: 48000,
      channels: 2
    ))
    let buffer = try XCTUnwrap(Pcm16PlaybackBuffer.make(
      data: Data([0x00, 0x40, 0x00, 0xC0, 0x00, 0x20, 0x00, 0xE0]),
      format: format
    ))
    let channels = try XCTUnwrap(buffer.floatChannelData)

    XCTAssertEqual(buffer.frameLength, 2)
    XCTAssertEqual(channels[0][0], 0.5)
    XCTAssertEqual(channels[1][0], -0.5)
    XCTAssertEqual(channels[0][1], 0.25)
    XCTAssertEqual(channels[1][1], -0.25)
  }

  func testIncompleteTrailingStereoFrameIsNotRead() throws {
    let format = try XCTUnwrap(AVAudioFormat(
      standardFormatWithSampleRate: 16000,
      channels: 2
    ))
    let buffer = try XCTUnwrap(Pcm16PlaybackBuffer.make(
      data: Data([0x00, 0x40, 0x00, 0xC0, 0xFF, 0x7F, 0xFF]),
      format: format
    ))

    XCTAssertEqual(buffer.frameLength, 1)
    XCTAssertNil(Pcm16PlaybackBuffer.make(data: Data([0x01, 0x02, 0x03]), format: format))
    XCTAssertNil(Pcm16PlaybackBuffer.make(data: Data(), format: format))
  }

  func testConvertedBufferFormatConnectsPlayerToMixer() throws {
    let format = try XCTUnwrap(AVAudioFormat(
      standardFormatWithSampleRate: 16000,
      channels: 1
    ))
    let buffer = try XCTUnwrap(Pcm16PlaybackBuffer.make(
      data: Data([0x00, 0x40]),
      format: format
    ))
    let engine = AVAudioEngine()
    let player = AVAudioPlayerNode()
    engine.attach(player)
    engine.connect(player, to: engine.mainMixerNode, format: buffer.format)

    XCTAssertTrue(player.outputFormat(forBus: 0).isStandard)
    XCTAssertEqual(player.outputFormat(forBus: 0).sampleRate, 16000)
  }
}
