unit VideoTrackerFrm;

interface

uses
  System.SysUtils, System.Types, System.UITypes, System.Classes, System.Variants,
  FMX.Types, FMX.Controls, FMX.Forms, FMX.Graphics, FMX.Dialogs, FMX.Controls.Presentation,
  FMX.StdCtrls, FMX.Objects, FMX.ScrollBox, FMX.Memo, FMX.Layouts, FMX.ExtCtrls,

  System.IOUtils,

  CoreClasses, zAI, zAI_Common, zDrawEngineInterface_SlowFMX, zDrawEngine, MemoryRaster, MemoryStream64,
  PascalStrings, UnicodeMixedLib, Geometry2DUnit, Geometry3DUnit, Cadencer, Y4M, h264Image;

type
  TForm1 = class(TForm, ICadencerProgressInterface)
    Memo1: TMemo;
    PaintBox1: TPaintBox;
    Timer1: TTimer;
    Tracker_CheckBox: TCheckBox;
    HistogramEqualizeCheckBox: TCheckBox;
    AntialiasCheckBox: TCheckBox;
    SepiaCheckBox: TCheckBox;
    SharpenCheckBox: TCheckBox;
    procedure FormCreate(Sender: TObject);
    procedure Timer1Timer(Sender: TObject);
    procedure PaintBox1Paint(Sender: TObject; Canvas: TCanvas);
  private
    procedure CadencerProgress(const deltaTime, newTime: Double);
  public
    drawIntf: TDrawEngineInterface_FMX;
    mpeg_y4m: TY4MReader;
    frame: TDETexture;
    cadencer_eng: TCadencer;
    ai: TAI;
    mmod_hnd: TMMOD_Handle;
    tracker_hnd: TTracker_Handle;
  end;

var
  Form1: TForm1;

implementation

{$R *.fmx}


uses ShowImageFrm;

procedure TForm1.FormCreate(Sender: TObject);
begin
  // ��ȡzAI������
  ReadAIConfig;

  // ��һ��������Key����������֤ZAI��Key
  // ���ӷ�������֤Key������������ʱһ���Ե���֤��ֻ�ᵱ��������ʱ�Ż���֤��������֤����ͨ����zAI����ܾ�����
  // �ڳ��������У���������TAI�����ᷢ��Զ����֤
  // ��֤��Ҫһ��userKey��ͨ��userkey�����ZAI������ʱ���ɵ����Key��userkey����ͨ��web���룬Ҳ������ϵ���߷���
  // ��֤key���ǿ����Ӽ����޷����ƽ�
  zAI.Prepare_AI_Engine();

  // ʹ��zDrawEngine���ⲿ��ͼʱ(������Ϸ������paintbox)������Ҫһ����ͼ�ӿ�
  // TDrawEngineInterface_FMX������FMX�Ļ�ͼcore�ӿ�
  // �����ָ����ͼ�ӿڣ�zDrawEngine��Ĭ��ʹ�������դ��ͼ(�Ƚ���)
  drawIntf := TDrawEngineInterface_FMX.Create;

  // mpeg yv12��Ƶ֡��ʽ
  mpeg_y4m := TY4MReader.Create(umlCombineFileName(TPath.GetLibraryPath, 'dog.y4m'));

  // ��ǰ���Ƶ���Ƶ֡
  frame := TDrawEngine.NewTexture;

  // cadencer����
  cadencer_eng := TCadencer.Create;
  cadencer_eng.ProgressInterface := Self;

  // ai����
  ai := TAI.OpenEngine();

  // ����dnn-od�ļ����
  mmod_hnd := ai.MMOD_DNN_Open_Stream(umlCombineFileName(TPath.GetLibraryPath, 'dog.svm_dnn_od'));

  // ��ʼ��׷����
  tracker_hnd := nil;
end;

procedure TForm1.Timer1Timer(Sender: TObject);
begin
  cadencer_eng.Progress;
end;

procedure TForm1.PaintBox1Paint(Sender: TObject; Canvas: TCanvas);
  procedure Raster_DetectAndDraw(mr: TMemoryRaster);
  var
    d: TDrawEngine;
    mmod_desc: TMMOD_Desc;
    tracker_r: TRectV2;
  begin
    // ʹ��dnn-od�����С��
    mmod_desc := ai.MMOD_DNN_Process(mmod_hnd, mr);

    d := TDrawEngine.Create;
    d.ViewOptions := [];

    // drawEngine�������ʽ��ֱ���ڴ�ӳ��
    // ���ַ�ʽ��0����copy��ֱ��д�뵽mr��bit�ڴ�
    // ���Ǵ���ffmpeg��Ƶ��������ʹ��drawengineʵ��������ͼ����Ϊ���������κζ��������copy
    d.Rasterization.Memory.SetWorkMemory(mr);
    d.SetSize(mr);

    // �ж��Ƿ��⵽С��
    if length(mmod_desc) = 0 then
      begin
        if Tracker_CheckBox.IsChecked then
          if tracker_hnd <> nil then
            begin
              // ���odû�м�⵽С������������ȷ��׷�����ǿ����ģ���ʼ׷����һ��od�ɹ��Ŀ���
              ai.Tracker_UpdateV2(tracker_hnd, mr, tracker_r);
              // ��tracker׷�����Ŀ����Էۺ�ɫ������
              d.DrawCorner(TV2Rect4.Init(tracker_r, 45), DEColor(1, 0.5, 0.5, 1), 20, 3);
            end;
      end
    else
      begin
        // ���OD������С��
        // �����ؿ�һ��׷����
        // TrackerҲ�Ƕ�һ���������ѧϰ������������od���������ܶ���������tracker������ʵʱѧϰ��
        ai.Tracker_Close(tracker_hnd);

        if Tracker_CheckBox.IsChecked then
          begin
            tracker_hnd := ai.Tracker_OpenV2(mr, mmod_desc[0].R);
            ai.Tracker_UpdateV2(tracker_hnd, mr, tracker_r);
            // ��tracker׷�����Ŀ����Էۺ�ɫ������
            d.DrawCorner(TV2Rect4.Init(tracker_r, 45), DEColor(1, 0.5, 0.5, 1), 20, 3);
          end;

        // ��OD�Ŀ�������ɫ������
        d.DrawCorner(TV2Rect4.Init(mmod_desc[0].R, 0), DEColor(0.5, 0.5, 1, 1), 20, 2);
      end;

    // ִ�л�ͼ��ָ��
    d.Flush;
    disposeObject(d);

    // ������ʾ�˶���Ƶ��������ڴ���Ĳ��ַ���

    // Sepia�Ƿǳ�Ư����ɫ��ϵ�����������������
    if SepiaCheckBox.IsChecked then
        Sepia32(mr, 16);

    // ʹ��ɫ��ֱ��ͼ�޸�yv12��ʧ��ɫ��
    // ��ͼ��������������е��Ӹо�
    if HistogramEqualizeCheckBox.IsChecked then
        HistogramEqualize(mr);

    // �����
    if AntialiasCheckBox.IsChecked then
        Antialias32(mr, 1);

    // ��
    if SharpenCheckBox.IsChecked then
        Sharpen(mr, False);
  end;

var
  d: TDrawEngine;
begin
  drawIntf.SetSurface(Canvas, Sender);
  d := DrawPool(Sender, drawIntf);
  d.ViewOptions := [devpFPS];
  d.FPSFontColor := DEColor(0.5, 0.5, 1, 1);

  mpeg_y4m.ReadFrame();
  YV12ToRaster(mpeg_y4m.Image, frame);
  Raster_DetectAndDraw(frame);
  frame.FastUpdateTexture;

  d.DrawTexture(frame, frame.BoundsRectV2, d.ScreenRect, 1.0);

  if mpeg_y4m.CurrentFrame >= mpeg_y4m.FrameCount then
    begin
      mpeg_y4m.SeekFirstFrame;
      d.LastNewTime := 0;
      ai.Tracker_Close(tracker_hnd);
    end;

  // ִ�л�ͼָ��
  d.Flush;
end;

procedure TForm1.CadencerProgress(const deltaTime, newTime: Double);
begin
  EnginePool.Progress(deltaTime);
  Invalidate;
end;

end.
