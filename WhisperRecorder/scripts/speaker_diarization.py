#!/usr/bin/env python3
"""
Speaker Diarization Script for WhisperRecorder
Uses pyannote.audio for real speaker detection and segmentation
"""

import sys
import json
import argparse
import os
import logging
from pathlib import Path
from typing import Dict, List, Any, Optional

try:
    import torch
    from pyannote.audio import Pipeline
    import torchaudio
except ImportError as e:
    print(json.dumps({
        "error": f"Missing dependencies: {e}. Please install: pip install pyannote.audio torch torchaudio"
    }))
    sys.exit(1)

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class SpeakerDiarizationProcessor:
    def __init__(self, model_name: str = "pyannote/speaker-diarization-3.1"):
        """
        Initialize the speaker diarization processor
        
        Args:
            model_name: HuggingFace model name for speaker diarization
        """
        self.model_name = model_name
        self.pipeline = None
        self._initialize_pipeline()
    
    def _initialize_pipeline(self):
        """Initialize the pyannote.audio pipeline"""
        try:
            # Check if CUDA is available
            device = "cuda" if torch.cuda.is_available() else "cpu"
            logger.info(f"Using device: {device}")
            
            # Load the pipeline
            logger.info(f"Loading speaker diarization model: {self.model_name}")
            self.pipeline = Pipeline.from_pretrained(
                self.model_name,
                use_auth_token=os.getenv("HUGGINGFACE_TOKEN")  # Optional: for gated models
            )
            
            # Move to device
            if device == "cuda":
                self.pipeline.to(torch.device("cuda"))
                
            logger.info("Pipeline initialized successfully")
            
        except Exception as e:
            logger.error(f"Failed to initialize pipeline: {e}")
            raise
    
    def process_audio(
        self, 
        audio_path: str, 
        min_speakers: Optional[int] = None,
        max_speakers: Optional[int] = None,
        progress_callback: Optional[callable] = None
    ) -> Dict[str, Any]:
        """
        Process audio file for speaker diarization
        
        Args:
            audio_path: Path to audio file
            min_speakers: Minimum number of speakers (optional)
            max_speakers: Maximum number of speakers (optional)
            progress_callback: Callback for progress updates
            
        Returns:
            Dictionary with diarization results
        """
        try:
            # Validate audio file
            if not os.path.exists(audio_path):
                raise FileNotFoundError(f"Audio file not found: {audio_path}")
            
            logger.info(f"Processing audio file: {audio_path}")
            
            # Load audio file info
            audio_info = torchaudio.info(audio_path)
            duration = audio_info.num_frames / audio_info.sample_rate
            
            logger.info(f"Audio duration: {duration:.2f} seconds")
            logger.info(f"Sample rate: {audio_info.sample_rate} Hz")
            logger.info(f"Channels: {audio_info.num_channels}")
            
            # Configure pipeline parameters
            pipeline_params = {}
            if min_speakers is not None:
                pipeline_params["min_speakers"] = min_speakers
            if max_speakers is not None:
                pipeline_params["max_speakers"] = max_speakers
            
            # Run diarization
            logger.info("Running speaker diarization...")
            if progress_callback:
                progress_callback(0.1)
            
            diarization = self.pipeline(audio_path, **pipeline_params)
            
            if progress_callback:
                progress_callback(0.9)
            
            # Process results
            results = self._process_diarization_results(diarization, duration)
            
            if progress_callback:
                progress_callback(1.0)
            
            logger.info(f"Diarization completed: {results['speaker_count']} speakers, {len(results['segments'])} segments")
            
            return {
                "success": True,
                "results": results,
                "audio_info": {
                    "duration": duration,
                    "sample_rate": audio_info.sample_rate,
                    "channels": audio_info.num_channels
                }
            }
            
        except Exception as e:
            logger.error(f"Error processing audio: {e}")
            return {
                "success": False,
                "error": str(e)
            }
    
    def _process_diarization_results(self, diarization, total_duration: float) -> Dict[str, Any]:
        """Process pyannote diarization results into our format"""
        segments = []
        speakers = set()
        
        for turn, _, speaker in diarization.itertracks(yield_label=True):
            segment = {
                "speaker_id": speaker,
                "start_time": turn.start,
                "end_time": turn.end,
                "duration": turn.end - turn.start,
                "confidence": 1.0  # pyannote doesn't provide confidence scores directly
            }
            segments.append(segment)
            speakers.add(speaker)
        
        # Sort segments by start time
        segments.sort(key=lambda x: x["start_time"])
        
        # Calculate speaker statistics
        speaker_stats = {}
        for speaker in speakers:
            speaker_segments = [s for s in segments if s["speaker_id"] == speaker]
            total_time = sum(s["duration"] for s in speaker_segments)
            speaker_stats[speaker] = {
                "total_time": total_time,
                "segment_count": len(speaker_segments),
                "percentage": (total_time / total_duration) * 100 if total_duration > 0 else 0
            }
        
        return {
            "segments": segments,
            "speaker_count": len(speakers),
            "unique_speakers": sorted(list(speakers)),
            "speaker_stats": speaker_stats,
            "total_duration": total_duration
        }

def main():
    """Main function for command-line usage"""
    parser = argparse.ArgumentParser(description="Speaker Diarization using pyannote.audio")
    parser.add_argument("audio_path", help="Path to audio file")
    parser.add_argument("--output", "-o", help="Output JSON file path", required=True)
    parser.add_argument("--min-speakers", type=int, help="Minimum number of speakers")
    parser.add_argument("--max-speakers", type=int, help="Maximum number of speakers")
    parser.add_argument("--model", default="pyannote/speaker-diarization-3.1", help="Model name")
    parser.add_argument("--progress-file", help="File to write progress updates")
    
    args = parser.parse_args()
    
    def progress_callback(progress: float):
        """Callback to write progress to file"""
        if args.progress_file:
            try:
                with open(args.progress_file, 'w') as f:
                    json.dump({"progress": progress}, f)
            except Exception as e:
                logger.warning(f"Could not write progress: {e}")
        
        logger.info(f"Progress: {progress * 100:.1f}%")
    
    try:
        # Initialize processor
        processor = SpeakerDiarizationProcessor(model_name=args.model)
        
        # Process audio
        results = processor.process_audio(
            audio_path=args.audio_path,
            min_speakers=args.min_speakers,
            max_speakers=args.max_speakers,
            progress_callback=progress_callback
        )
        
        # Write results to output file
        with open(args.output, 'w') as f:
            json.dump(results, f, indent=2)
        
        if results["success"]:
            logger.info(f"Results written to: {args.output}")
            print(json.dumps({"status": "success", "output_file": args.output}))
        else:
            logger.error(f"Processing failed: {results.get('error')}")
            print(json.dumps({"status": "error", "error": results.get("error")}))
            sys.exit(1)
            
    except Exception as e:
        logger.error(f"Unexpected error: {e}")
        error_result = {
            "success": False,
            "error": str(e)
        }
        
        with open(args.output, 'w') as f:
            json.dump(error_result, f, indent=2)
        
        print(json.dumps({"status": "error", "error": str(e)}))
        sys.exit(1)

if __name__ == "__main__":
    main() 